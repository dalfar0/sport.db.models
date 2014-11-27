# encoding: utf-8

##############
# nb: for local testing use:
#    
#  ruby -I ../../github/sport.db.ruby/lib
#        ../../github/sport.db.ruby/lib/sportdb.rb
#        setup --delete --sport
#        --include ../../github/football.db


require 'gli'
 
include GLI::App

# our own code / additional for cli only

require 'logutils/db'
require 'sportdb/cli/opts'

require 'datafile'   ## lets us use Datafile::Builder,Datafile etc.


program_desc 'sport.db command line tool'

version SportDb::VERSION


LogUtils::Logger.root.level = :info   # set logging level to info 
logger = LogUtils::Logger.root


=begin
### add to help use new sections

Examples:
    sportdb cl/teams cl/2012_13/cl                     # import champions league (cl)
    sportdb --create                                   # create database schema

More Examples:
    sportdb                                            # show stats (table counts, table props)
    sportdb -i ../sport.db/db cl/teams cl/2012_13/cl   # import champions league (cl) in db folder

Further information:
  http://geraldb.github.com/sport.db
=end


## todo: find a better name e.g. change to settings? config? safe_opts? why? why not?
opts = SportDb::Opts.new

### global option (required)
## todo: add check that path is valid?? possible?


desc 'Database path'
arg_name 'PATH'
default_value opts.db_path
flag [:d, :dbpath]

desc 'Database name'
arg_name 'NAME'
default_value opts.db_name
flag [:n, :dbname]

desc '(Debug) Show debug messages'
switch [:verbose], negatable: false    ## todo: use -w for short form? check ruby interpreter if in use too?

desc 'Only show warnings, errors and fatal messages'
switch [:q, :quiet], negatable: false



def connect_to_db( options )
  puts SportDb.banner

  puts "working directory: #{Dir.pwd}"

  db_config = {
    :adapter  => 'sqlite3',
    :database => "#{options.db_path}/#{options.db_name}"
  }

  ## todo/check: use if defined?( JRUBY_VERSION ) instead ??
  if RUBY_PLATFORM =~ /java/ && db_config[:adapter] == 'sqlite3' 
    # quick hack for JRuby sqlite3 support via jdbc
    require 'jdbc/sqlite3'
    ## todo: check if require for activerecord jdbc adapter for sqlite is required to
  end


  puts "Connecting to db using settings: "
  pp db_config

  ActiveRecord::Base.establish_connection( db_config )
  
  LogDb.setup  # start logging to db
end


desc 'Create DB schema'
command [:create] do |c|
  c.action do |g,o,args|
    
    connect_to_db( opts )
    
    LogDb.create
    ConfDb.create
    TagDb.create
    WorldDb.create
    PersonDb.create
    SportDb.create
    
    SportDb.read_builtin   # e.g. seasons.txt etc
    
    puts 'Done.'
  end # action
end # command create


desc "Build DB (download/create/read); use ./Datafile - zips get downloaded to ./tmp"
command [:build,:b] do |c|

  c.action do |g,o,args|

    builder = Datafile::Builder.load_file( './Datafile' )
    datafile = builder.datafile
    datafile.download  # datafile step 1 - download all datasets/zips 

    connect_to_db( opts )

    LogDb.create
    ConfDb.create
    TagDb.create
    WorldDb.create
    PersonDb.create
    SportDb.create

    SportDb.read_builtin   # e.g. seasons.txt etc

    datafile.read  # datafile step 2 - read all datasets

    puts 'Done.'
  end # action
end  # command setup


desc "Read datasets; use ./Datafile - zips required in ./tmp"
command [:read,:r] do |c|

  c.action do |g,o,args|

    connect_to_db( opts )

    builder = Datafile::Builder.load_file( './Datafile' )
    datafile = builder.datafile
    datafile.read

    puts 'Done.'
  end # action
end  # command setup

desc "Download datasets; use ./Datafile - zips get downloaded to ./tmp"
command [:download,:dl] do |c|

  c.action do |g,o,args|

    # note: no database connection needed (check - needed for logs?? - not setup by default???)

    builder = Datafile::Builder.load_file( './Datafile' )
    datafile = builder.datafile
    datafile.download

    puts 'Done.'
  end # action
end  # command setup


desc "Build DB w/ quick starter Datafile templates"
arg_name 'NAME'   # optional setup profile name
command [:new,:n] do |c|

  c.action do |g,o,args|

    ## todo: required template name (defaults to worldcup2014)
    setup = args[0] || 'worldcup2014'

    worker = Fetcher::Worker.new
    worker.copy( "https://github.com/openfootball/datafile/raw/master/#{setup}.rb", './Datafile' )

    ## step 2: same as command build (todo - reuse code)
    builder = Datafile::Builder.load_file( './Datafile' )
    datafile = builder.datafile
    datafile.download  # datafile step 1 - download all datasets/zips 

    connect_to_db( opts )  ### todo: check let connect go first?? - for logging (logs) to db  ???

    LogDb.create
    ConfDb.create
    TagDb.create
    WorldDb.create
    PersonDb.create
    SportDb.create

    SportDb.read_builtin   # e.g. seasons.txt etc

    datafile.read  # datafile step 2 - read all datasets

    puts 'Done.'
  end # action
end  # command setup



desc "Create DB schema 'n' load all world and sports data"
arg_name 'NAME'   # optional setup profile name
command [:setup,:s] do |c|

  c.desc 'Sports data path'
  c.arg_name 'PATH'
  c.default_value opts.data_path
  c.flag [:i,:include]

  c.desc 'World data path'
  c.arg_name 'PATH'
  c.flag [:worldinclude]   ## todo: use --world-include - how? find better name? add :'world-include' ???

  c.action do |g,o,args|

    connect_to_db( opts )
 
    ## todo: document optional setup profile arg (defaults to all)
    setup = args[0] || 'all'
    
    LogDb.create
    ConfDb.create
    TagDb.create
    WorldDb.create
    PersonDb.create
    SportDb.create

    SportDb.read_builtin   # e.g. seasons.txt etc
    
    WorldDb.read_all( opts.world_data_path )
    SportDb.read_setup( "setups/#{setup}", opts.data_path )
    puts 'Done.'
  end # action
end  # command setup


desc 'Update all sports data'
arg_name 'NAME'   # optional setup profile name
command [:update,:up,:u] do |c|

  c.desc 'Sports data path'
  c.arg_name 'PATH'
  c.default_value opts.data_path
  c.flag [:i,:include]

  c.desc 'Delete all sports data records'
  c.switch [:delete], negatable: false 

  c.action do |g,o,args|

    connect_to_db( opts )

    ## todo: document optional setup profile arg (defaults to all)
    setup = args[0] || 'all'

    if o[:delete].present?
      SportDb.delete! 
      SportDb.read_builtin    # NB: reload builtins (e.g. seasons etc.)
    end

    SportDb.read_setup( "setups/#{setup}", opts.data_path )
    puts 'Done.'
  end # action
end  # command setup


desc 'Load sports fixtures'
arg_name 'NAME'   # multiple fixture names - todo/fix: use multiple option
command [:load, :l] do |c|

  c.desc 'Delete all sports data records'
  c.switch [:delete], negatable: false 

  c.action do |g,o,args|

    connect_to_db( opts )
    
    if o[:delete].present?
      SportDb.delete!
      SportDb.read_builtin    # NB: reload builtins (e.g. seasons etc.)
    end

    reader = SportDb::Reader.new( opts.data_path )

    args.each do |arg|
      name = arg     # File.basename( arg, '.*' )
      reader.load( name )
    end # each arg

    puts 'Done.'
  end
end # command load


if defined?( SportDb::Updater )   ## add only if Updater class loaded/defined

desc 'Pull - Auto-update event fixtures from upstream online sources'
command :pull do |c|
  c.action do |g,o,args|

    connect_to_db( opts )

    SportDb.update!

    puts 'Done.'
  end # action
end # command pull

end  ## if defined?( SportDb::Updater )



desc 'Start web service (HTTP JSON API)'
command [:serve,:server] do |c|

  c.action do |g,o,args|

    connect_to_db( opts )

    # note: server (HTTP service) not included in standard default require
    ##   -- note - now included!!!
    ## require 'sportdb/service'

# make sure connections get closed after every request e.g.
#
#  after do
#   ActiveRecord::Base.connection.close
#  end
#

    puts 'before add middleware ConnectionManagement'
    SportDb::Service::Server.use ActiveRecord::ConnectionAdapters::ConnectionManagement
    puts 'after add middleware ConnectionManagement'
    ## todo: check if we can check on/dump middleware stack

    ## rack middleware might not work with multi-threaded thin web server; close it ourselfs
    SportDb::Service::Server.after do
      puts "  #{Thread.current.object_id} -- make sure db connections gets closed after request"
      # todo: check if connection is open - how? 
      ActiveRecord::Base.connection.close
    end    

    SportDb::Service::Server.run!

    puts 'Done.'
  end
end # command serve



desc 'Show logs'
command :logs do |c|
  c.action do |g,o,args|

    connect_to_db( opts ) 
    
    LogDb::Models::Log.all.each do |log|
      puts "[#{log.level}] -- #{log.msg}"
    end
    
    puts 'Done.'
  end
end


desc 'Show stats'
command :stats do |c|
  c.action do |g,o,args|

    connect_to_db( opts )
    
    SportDb.tables
    WorldDb.tables
    
    puts 'Done.'
  end
end


desc 'Show props'
command :props do |c|
  c.action do |g,o,args|

    connect_to_db( opts )
    
    SportDb.props
    
    puts 'Done.'
  end
end


desc '(Debug) Test command suite'
command :test do |c|
  c.action do |g,o,args|

    puts "hello from test command"
    puts "args (#{args.class.name}):"
    pp args
    puts "o (#{o.class.name}):"
    pp o
    puts "g (#{g.class.name}):"
    pp g

    logger = LogUtils::Logger.root
    logger.debug 'test debug msg'
    logger.info 'test info msg'
    logger.warn 'test warn msg'

    puts 'Done.'
  end
end



pre do |g,c,o,args|
  opts.merge_gli_options!( g )
  opts.merge_gli_options!( o )

  puts SportDb.banner

  if opts.verbose?
    LogUtils::Logger.root.level = :debug
  end

  logger.debug "Executing #{c.name}"   
  true
end

post do |global,c,o,args|
  logger.debug "Executed #{c.name}"
  true
end


on_error do |e|
  puts
  puts "*** error: #{e.message}"

  if opts.verbose?
    puts e.backtrace
  end

  false # skip default error handling
end


exit run(ARGV)