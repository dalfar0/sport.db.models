# encoding: UTF-8

module SportDb


class EventReader

  include LogUtils::Logging

## make models available by default with namespace
#  e.g. lets you use Usage instead of Model::Usage
  include Models

  attr_reader :event           # returns event record; call read first
  attr_reader :fixtures        #  fixtures/sources entry from event config

  def self.from_zip( zip_file, entry_path, more_attribs={} )
    ## get text content from zip
    entry = zip_file.find_entry( entry_path )

    text = entry.get_input_stream().read()
    text = text.force_encoding( Encoding::UTF_8 )

    config = File.basename( entry_path )  # name a of .yml file

    self.from_string( text, config, more_attribs )
  end

  def self.from_file( path, more_attribs={} )
    ## note: assume/enfore utf-8 encoding (with or without BOM - byte order mark)
    ## - see textutils/utils.rb
    text = File.read_utf8( path )
    
    config = File.basename( name )  # name a of .yml file
    
    self.from_string( text, config, more_attribs )
  end

  def self.from_string( text, config, more_attribs={} )
    EventReader.new( text, config, more_attribs )
  end  

  def initialize( text, config, more_attribs={} )
    ## todo/fix: how to add opts={} ???
    @text = text
    @more_attribs = more_attribs

    @config          = config   # name of  event configuration (relative basename w/o path or string)
    @sources_default = config   # note: use same a config for now

    @event    = nil
    @fixtures = []
  end


  def read
    @fixtures = []    # reset cached fixtures
    @event    = nil   # reset cached event rec

####
## fix!!!!!
##   use Event.create_or_update_from_hash or similar
##   use Event.create_or_update_from_hash_reader?? or similar
#   move parsing code to model

    reader = HashReader.from_string( @text )

    event_attribs = {}

    ## set default sources to basename by convention
    #  e.g  2013_14/bl  => bl
    #  etc.
    # use fixtures/sources: to override default

    event_attribs[ 'sources' ] = @sources_default
    event_attribs[ 'config'  ] = @config            # name a of .yml file

    reader.each_typed do |key, value|

      ## puts "processing event attrib >>#{key}<< >>#{value}<<..."

      if key == 'league'
        league = League.find_by_key( value.to_s.strip )

        ## check if it exists
        if league.present?
          event_attribs['league_id'] = league.id
        else
          logger.error "league with key >>#{value.to_s.strip}<< missing"
          exit 1
        end
       
      elsif key == 'season'
        season = Season.find_by_key( value.to_s.strip )

        ## check if it exists
        if season.present?
          event_attribs['season_id'] = season.id
        else
          logger.error "season with key >>#{value.to_s.strip}<< missing"
          exit 1
        end
        
      elsif key == 'start_at' || key == 'begin_at'
        
        if value.is_a?(DateTime) || value.is_a?(Date)
          start_at = value
        else # assume it's a string
          start_at = DateTime.strptime( value.to_s.strip, '%Y-%m-%d' )
        end
        
        event_attribs['start_at'] = start_at

      elsif key == 'end_at' || key == 'stop_at'
        
        if value.is_a?(DateTime) || value.is_a?(Date)
          end_at = value
        else # assume it's a string
          end_at = DateTime.strptime( value.to_s.strip, '%Y-%m-%d' )
        end
        
        event_attribs['end_at'] = end_at

      elsif key == 'grounds' || key == 'stadiums' || key == 'venues'
        ## assume grounds value is an array
        
        ##
        ## note: for now we allow invalid ground keys
        ##  will skip keys not found
        
        ground_ids = []
        value.each do |item|
          ground_key = item.to_s.strip
          ground = Ground.find_by_key( ground_key )
          if ground.nil?
            puts "[warn] ground/stadium w/ key >#{ground_key}< not found; skipping ground"
          else
            ground_ids << ground.id
          end
        end

        event_attribs['ground_ids'] = ground_ids
      elsif key == 'teams'
        ## assume teams value is an array
        
        team_ids = []
        value.each do |item|
          team_key = item.to_s.strip
          team = Team.find_by_key( team_key )
          if team.nil?
            ### print better error message than just
            ##  *** error: Couldn't find SportDb::Model::Team
            puts "[fatal] event reader - team keys: #{value.inspect}"
            puts "[fatal] event reader - record for team key >#{team_key}< not found"
            exit 1
            ### fix/todo: throw exception/error
          end
          team_ids << team.id
        end

        event_attribs['team_ids'] = team_ids
        
      elsif key == 'team3'
        ## for now always assume false  # todo: fix - use value and convert to boolean if not boolean
        event_attribs['team3'] = false

      elsif key == 'fixtures' || key == 'sources'
        ### todo: check for mulitiple fixtures/sources ?? allow disallow?? why? why not?
        if value.kind_of?(Array)
          event_attribs['sources'] = value.join(',')
          @fixtures += value
        else # assume plain (single fixture) string
          event_attribs['sources'] = value.to_s
          @fixtures << value.to_s
        end
      else
        ## todo: add a source location struct to_s or similar (file, line, col)
        logger.error "unknown event attrib #{key}; skipping attrib"
      end

    end # each key,value

    league_id = event_attribs['league_id']
    season_id = event_attribs['season_id']

    logger.debug "find event - league_id: #{league_id}, season_id: #{season_id}"

    event = Event.find_by_league_id_and_season_id( league_id, season_id )

    ## check if it exists
    if event.present?
      logger.debug "*** update event #{event.id}-#{event.key}:"
    else
      logger.debug "*** create event:"
      event = Event.new
    end
    
    logger.debug event_attribs.to_json

    event.update_attributes!( event_attribs )
    
    # keep a cached reference for later use
    @event = event
  end  # method read


end # class EventReader
end # module SportDb
