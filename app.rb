require 'sinatra'
require 'koala'
require 'data_mapper'
require 'dm-migrations'
require 'logger'
require 'json'

enable :sessions
DataMapper.setup(:default, ENV['DATABASE_URL'] || "mysql://root:900@localhost/todofb_development")
ENV['FACEBOOK_APP_ID'] = '202941423160360'
ENV['FACEBOOK_SECRET'] = '1bd559c64cd31200178dc702ed3125f3'

configure :production do
  disable :raise_errors, :show_exceptions, :logging
end

configure :development do 
  set :port, '9393'
  #Log = Logger.new("public/sinatra.log.txt")
  #Log.level  = Logger::INFO 
  enable :logging, :dump_errors, :raise_errors, :show_exceptions
end

class Todo
  include DataMapper::Resource

  property :id,         Serial
  property :user_id,    Integer#, :key => true
  property :task,       String
  property :closed,     Boolean, :default => 0
  property :closed_at,  DateTime
  property :created_at, DateTime
  property :updated_at, DateTime

  validates_presence_of :task
  validates_length_of   :task, :minimum => 1
end
# DataMapper.auto_migrate!
DataMapper.finalize

# facebook ACL and ENV check
FACEBOOK_SCOPE = 'user_likes,user_photos,user_photo_video_tags'
unless ENV["FACEBOOK_APP_ID"] && ENV["FACEBOOK_SECRET"]
  abort("missing env vars: please set FACEBOOK_APP_ID and FACEBOOK_SECRET with your app credentials")
end

before do
  @app = { name: 'ToDoIt' }
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
    @user = {}
    if(settings.environment == :development)
      @user[:id] = 100
    end    
  end

  def task_tag(task)
    del = '<a href="javascript:TODO.del('+task.id.to_s+')" class="del">x</a>'
    '<li id="li-'+task.id.to_s+'"><input type="checkbox" name="task[]" id="check-'+task.id.to_s+'" value="'+task.id.to_s+'" /> '+task.task+del+'</li>'
  end

end


post "/" do
  redirect "/"
end

# Work Application

get "/" do
  layout :layout
  current_user
  @tasks = Todo.all(user_id: @user[:id], order: [:created_at.desc], closed: 0 )
  erb :index
end

put '/task' do
  id = params[:id]
  return {error: 'Sorry, no id, no cry'}.to_json unless id
  task = Todo.get(id)
  task.update(closed: 1, closed_at: Time.now)
  if request.xhr?
    {id: task.id}.to_json
  else
    redirect '/'
  end
end

delete '/task' do
  id = params[:id]
  return { error: 'Sorry, no id, no cry' }.to_json unless id
  task = Todo.get(id)
  task.destroy
  if request.xhr?
    {id: task.id}.to_json
  else
    redirect '/'
  end
end

post '/task' do
  current_user
  todo = Todo.create(task: params[:task], user_id: @user[:id])
  if todo.save
  else
    todo.errors.each do |error|
      puts error
    end
  end
  if request.xhr?
    task = Todo.last
    {id: task[:id], task: task[:task], html: task_tag(task) }.to_json
  else
    redirect '/'
  end
end

# Facebook