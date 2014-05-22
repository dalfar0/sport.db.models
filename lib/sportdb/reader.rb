# encoding: utf-8

module SportDb

class Reader

  include LogUtils::Logging


## make models available in sportdb module by default with namespace
#  e.g. lets you use Team instead of Model::Team
  include SportDb::Models
  include SportDb::Matcher # lets us use match_teams_for_country etc.


  attr_reader :include_path

  def initialize( include_path, opts={})
    @include_path = include_path
  end

  def load_setup( name )
    path = "#{include_path}/#{name}.txt"
    
    ## depcrecated - for now check if "new" format exsits
    ##  - if not fall back to old format
    unless File.exists?( path )
      puts "  deprecated manifest/setup format [SportDb.Reader]; use new plain text format"
      ## try old yml format
      path = "#{include_path}/#{name}.yml"
    end

    logger.info "parsing data '#{name}' (#{path})..."

    reader = FixtureReader.new( path )

    reader.each do |fixture_name|
      load( fixture_name )
    end
  end # method load_setup


  def is_club_fixture?( name )
    ## guess (heuristic) if it's a national team event (e.g. world cup, copa america, etc.)
    ##  or club event (e.g. bundesliga, club world cup, etc.)

    if name =~ /club-world-cup!?\//      # NB: must go before -cup (special case)
      true
    elsif name =~ /copa-america!?\// ||  # NB: copa-america/ or copa-america!/
          name =~ /-cup!?\//             # NB: -cup/ or -cup!/
      false
    else
      true
    end
  end


  def load( name )   # convenience helper for all-in-one reader

    logger.debug "enter load( name=>>#{name}<<, include_path=>>#{include_path}<<)"

    if name  =~ /^circuits/  # e.g. circuits.txt in formula1.db
      reader = TrackReader.new( include_path )
      reader.read( name )
    elsif match_tracks_for_country( name ) do |country_key|  # name =~ /^([a-z]{2})\/tracks/
            # auto-add country code (from folder structure) for country-specific tracks
            #  e.g. at/tracks  or at-austria/tracks
            country = Country.find_by_key!( country_key )
            reader = TrackReader.new( include_path )
            reader.read( name, country_id: country.id )
          end
    elsif name  =~ /^tracks/  # e.g. tracks.txt in ski.db
      reader = TrackReader.new( include_path )
      reader.read( name )
    elsif name =~ /^drivers/ # e.g. drivers.txt in formula1.db
      reader = PersonDb::PersonReader.new( include_path )
      reader.read( name )
    elsif match_players_for_country( name ) do |country_key|
            country = Country.find_by_key!( country_key )
            reader = PersonDb::PersonReader.new( include_path )
            reader.read( name, country_id: country.id )
          end
    elsif match_skiers_for_country( name ) do |country_key|  # name =~ /^([a-z]{2})\/skiers/
            # auto-add country code (from folder structure) for country-specific skiers (persons)
            #  e.g. at/skiers  or at-austria/skiers.men
            country = Country.find_by_key!( country_key )
            reader = PersonDb::PersonReader.new( include_path )
            reader.read( name, country_id: country.id )
          end
    elsif name =~ /^skiers/ # e.g. skiers.men.txt in ski.db
      reader = PersonDb::PersonReader.new( include_path )
      reader.read( name )
    elsif name =~ /^teams/   # e.g. teams.txt in formula1.db
      reader = TeamReader.new( include_path )
      reader.read( name )
    elsif name =~ /\/races/  # e.g. 2013/races.txt in formula1.db
      ## fix/bug:  NOT working for now; sorry
      #   need to read event first and pass along to read (event_id: event.id) etc.
      reader = RaceReader.new( include_path )
      reader.read( name )
    elsif name =~ /\/squads\/([a-z]{2,3})-[^\/]+$/
      ## fix: add to country matcher new format
      ##   name is country! and parent folder is type name e.g. /squads/br-brazil
      country = Country.find_by_key!( $1 )
      reader = NationalTeamReader.new( include_path )
      ## note: pass in @event.id - that is, last seen event (e.g. parsed via GameReader/MatchReader)
      reader.read( name, country_id: country.id, event_id: @event.id )
    elsif name =~ /\/squads/ || name =~ /\/rosters/  # e.g. 2013/squads.txt in formula1.db
      reader = RaceTeamReader.new( include_path )
      reader.read( name )
    elsif name =~ /\/([0-9]{2})-/
      race_pos = $1.to_i
      # NB: assume @event is set from previous load 
      race = Race.find_by_event_id_and_pos( @event.id, race_pos )
      reader = RecordReader.new( include_path )
      reader.read( name, race_id: race.id ) # e.g. 2013/04-gp-monaco.txt in formula1.db
    elsif name =~ /(?:^|\/)seasons/  # NB: ^seasons or also possible at-austria!/seasons
      reader = SeasonReader.new( include_path )
      reader.read( name )
    elsif match_stadiums_for_country( name ) do |country_key|
            country = Country.find_by_key!( country_key )
            reader = GroundReader.new( include_path )
            reader.read( name, country_id: country.id )
          end
    elsif match_leagues_for_country( name ) do |country_key|  # name =~ /^([a-z]{2})\/leagues/
            # auto-add country code (from folder structure) for country-specific leagues
            #  e.g. at/leagues
            country = Country.find_by_key!( country_key )
            reader = LeagueReader.new( include_path )
            reader.read( name, club: true, country_id: country.id )
          end
    elsif name =~ /(?:^|\/)leagues/   # NB: ^leagues or also possible world!/leagues  - NB: make sure goes after leagues_for_country!!
      reader = LeagueReader.new( include_path )
      reader.read( name, club: is_club_fixture?( name ) )
    elsif match_teams_for_country( name ) do |country_key|   # name =~ /^([a-z]{2})\/teams/
            # auto-add country code (from folder structure) for country-specific teams
            #  e.g. at/teams at/teams.2 de/teams etc.                
            country = Country.find_by_key!( country_key )
            reader = TeamReader.new( include_path )
            reader.read( name, club: true, country_id: country.id )
          end
    elsif name =~ /(?:^|\/)teams/
      reader = TeamReader.new( include_path )
      reader.read( name, club: is_club_fixture?( name ) )
    elsif name =~ /\/(\d{4}|\d{4}_\d{2})(--[^\/]+)?\// ||
          name =~ /\/(\d{4}|\d{4}_\d{2})$/

      # note: keep a "public" reference of last event in @event  - e.g. used/required by squads etc.
      eventreader = EventReader.new( include_path )
      eventreader.read( name )
      @event    = eventreader.event

      # e.g. must match /2012/ or /2012_13/  or   /2012--xxx/ or /2012_13--xx/
      #  or   /2012 or /2012_13   e.g. brazil/2012 or brazil/2012_13
      reader = GameReader.new( include_path )
      reader.read( name )
    else
      logger.error "unknown sportdb fixture type >#{name}<"
      # todo/fix: exit w/ error
    end
  end # method load


end # class Reader
end # module SportDb
