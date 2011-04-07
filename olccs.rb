require 'singleton'

require 'uri'
require 'cgi'
require 'fiber'
require 'rack/fiber_pool'

require 'sinatra/base'

require 'nokogiri'
require 'yaml'
require 'json'

require 'eventmachine'
require 'em-synchrony'

require 'log4r'
include Log4r

require 'pp'

require_relative 'lib/es.rb'
require_relative 'lib/post.rb'
require_relative 'lib/board.rb'

log = Logger.new("olccs")

o = RollingFileOutputter.new("f1", :filename => "./olccs.log", :maxsize => 1048576, :maxtime => 86400)
o.formatter = PatternFormatter.new(:pattern => "[%l] %d :: %m")
log.outputters << o


class Configuration
  include Singleton
  
  attr_reader :boards, :es
  
  def init
    log = Log4r::Logger['olccs']
    config_global = YAML.load_file('config/config.yml')
    config_boards = YAML.load_file('config/boards.yml')
    
    @es = config_global['global']['es']
    #ES.instance.address=config_global['global']['es']
    
    @boards = Hash.new
    config_boards.each_pair do |b,c|
      @boards[b] = Board.new(b,c['getURL'],c['postURL'], c['postParameter'], c['lastIdParameter'] || "last")
      @boards[b].index
      log.info("Board #{b} initialized")

    end
    
  end
end

EM.synchrony do

  Configuration.instance.init

  EventMachine::PeriodicTimer.new(30) do
    Configuration.instance.boards.each_pair do |b,c|
      Fiber.new {
        new,total,secs = c.index
        log.info "#{c.name} indexed in #{secs} seconds, #{new} new posts"
      }.resume
    end      
  end

  class Olccs < Sinatra::Base
    
    use Rack::FiberPool
    use Rack::CommonLogger
    use Rack::Lint
    set :root, File.dirname(__FILE__) + '/static'

    configure do
      set(:boards) {
        Configuration.instance.boards
      }
    end

    get '/:n/xml' do |n|
      content_type :xml
      result = settings.boards[n].xml
      body result
    end
    
    get '/:n/json' do |n|
      content_type :json
      result = settings.boards[n].backend
      body result
    end
 
    post '/:n/post' do |n|
      content_type :text
      result = settings.boards[n].post(request.cookies, request.user_agent)
      body result
    end

    get '/backend.php' do
      content_type :xml

      log = Log4r::Logger['olccs']
      log.debug "+> BACKEND for #{params[:url]}"

      


      board = URI.parse(params[:url])
      board_name = board.host
      board_query = board.query
      log.debug "+> #{board_query}"
      l = CGI.parse(board_query)['last'][0]
      if l==nil or l == "" then
        l = -1
      end
        
      b = settings.boards.select { |k, v| URI.parse(v.getURL).host == board_name }
      result = b.to_a[0][1].xml(l) 
      body result
    end

    post '/post.php' do
      content_type :text
      log = Log4r::Logger['olccs']
      log.debug "+> POST for #{params[:posturl]}"

      board_name = URI.parse(params[:posturl]).host
      b = settings.boards.select { |k, v| URI.parse(v.postURL).host == board_name }.to_a[0][1]
      b.post(params[:cookie], params[:ua], params[:postdata])
      body "plop"
    end
    
    get '/' do
      body 'Hello World!'
    end
  end

  Olccs.run!

end
  
