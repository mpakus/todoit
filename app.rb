require 'sinatra'
require 'koala'
require 'data_mapper'
require 'dm-migrations'
require 'logger'
require 'json'

enable :sessions
DataMapper.setup(:default, ENV['DATABASE_URL'] || "mysql://root:900@localhost/todofb_development")

configure :production do
  enable :raise_errors, :show_exceptions, :logging
  disable :protection
  # set :protection, :except => [:task, :remote_token, :frame_options]
end

configure :development do 
  ENV['FACEBOOK_APP_ID'] = '202941423160360'
  ENV['FACEBOOK_SECRET'] =  '1bd559c64cd31200178dc702ed3125f3'
  set :port, '9393'
  Log = Logger.new("log/sinatra.log.txt")
  #Log.level  = Logger::INFO 
  enable :logging, :dump_errors, :raise_errors, :show_exceptions
end

class Todo
  include DataMapper::Resource

  property :id,         Serial
  # property :user_id,    String, :key => true, :length => 32 # :min => 0, :max => 2**64
  property :user_id,    Integer, :key => true, :min => 0, :max => 2**32
  property :task,       String
  property :closed,     Boolean, :default => 0
  property :closed_at,  DateTime
  property :created_at, DateTime
  property :updated_at, DateTime

  validates_presence_of :task
  validates_length_of   :task, :minimum => 1
end
DataMapper.auto_migrate!
DataMapper.finalize

# facebook ACL and ENV check
FACEBOOK_SCOPE = 'user_likes,user_photos,user_photo_video_tags'
unless ENV["FACEBOOK_APP_ID"] && ENV["FACEBOOK_SECRET"]
  abort("missing env vars: please set FACEBOOK_APP_ID and FACEBOOK_SECRET with your app credentials")
end

before do
  # @app = { name: 'ToDoIt' }
  # HTTPS redirect
  if settings.environment == :production && request.scheme != 'https'
    redirect "https://#{request.env['HTTP_HOST']}"
  end
end

helpers do
  def host
    request.env['HTTP_HOST']
  end

  def scheme
    request.scheme
  end

  def url_no_scheme(path = '')
    "//#{host}#{path}"
  end

  def url(path = '')
    "#{scheme}://#{host}#{path}"
  end

  def current_user
    # @user = {}
    # if(settings.environment == :development)
    #   @user[:id] = 100
    # else
      graph  = Koala::Facebook::API.new(session[:access_token])
      # @app  =  @graph.get_object(ENV["FACEBOOK_APP_ID"])

      if session[:access_token]
        return graph.get_object("me")
      end      
    # end    
  end

  def authenticator
    @authenticator ||= Koala::Facebook::OAuth.new(ENV["FACEBOOK_APP_ID"], ENV["FACEBOOK_SECRET"], url("/auth/facebook/callback"))
  end

  def task_tag(task)
    del = '<a href="javascript:TODO.del('+task.id.to_s+')" class="del">x</a>'
    '<li id="li-'+task.id.to_s+'"><input type="checkbox" name="task[]" id="check-'+task.id.to_s+'" value="'+task.id.to_s+'" /> '+task.task+del+'</li>'
  end

end

# the facebook session expired! reset ours and restart the process
error(Koala::Facebook::APIError) do
  session[:access_token] = nil
  redirect "/auth/facebook"
end

#--- Work Application

get '/' do
  layout :layout
  # current_user
  
  # Get base API Connection
  @graph  = Koala::Facebook::API.new(session[:access_token])
  # Get public details of current application
  @app  =  @graph.get_object(ENV["FACEBOOK_APP_ID"])

  if session[:access_token]
    @user    = @graph.get_object("me")
  end

  if @user
    @tasks = Todo.all(user_id: @user['id'].to_i, order: [:created_at.desc], closed: 0 )
  end
  erb :index
end

post '/' do
   redirect '/'
end

put '/task' do
  # @todo: need check task and user_id
  id = params[:task_id].to_i
  return {error: 'Sorry, no id, no cry'}.to_json unless id
  task = Todo.first( id: id)
  task.update(closed: 1, closed_at: Time.now)
  if request.xhr?
    {id: task.id}.to_json
  else
    redirect '/'
  end
end

delete '/task' do
  # @todo: need check task and user_id
  id = params[:task_id].to_i
  return { error: 'Sorry, no id, no cry' }.to_json unless id
  task = Todo.first( id: id)
  task.destroy
  if request.xhr?
    {id: task.id}.to_json
  else
    redirect '/'
  end
end

post '/task' do
  user_id = params[:id]
  return {error:"Access denied, you should be authorized"}.to_json unless user_id

  todo = Todo.create(task: params[:task].to_s, user_id: user_id.to_i)
  if todo.save
    if request.xhr?
      task = Todo.last
      return {id: task[:id], task: task[:task], html: task_tag(task) }.to_json
    else
      redirect '/'
    end
  else
    todo.errors.each do |error|
      # puts error
      logger.debug error
    end
  end
end

# Facebook

get "/close" do
  "<body onload='window.close();'/>"
end

get "/sign_out" do
  session[:access_token] = nil
  redirect '/'
end

get "/auth/facebook" do
  session[:access_token] = nil
  redirect authenticator.url_for_oauth_code(:permissions => FACEBOOK_SCOPE)
end

get '/auth/facebook/callback' do
  session[:access_token] = authenticator.get_access_token(params[:code])
  redirect '/'
end
