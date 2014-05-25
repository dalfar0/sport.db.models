# encoding: utf-8

module SportDb
  module Model


class AlltimeStandingEntry < ActiveRecord::Base

  self.table_name = 'alltime_standing_entries'

  belongs_to :standing, class_name: 'SportDb::Model::AlltimeStanding', foreign_key: 'alltime_standing_id'
  belongs_to :team

  ## note:
  ##  map standing_id to alltime_standing_id - convenience alias
  def standing_id=(value)  write_attribute(:alltime_standing_id, value);  end


end # class AlltimeStandingEntry


  end # module Model
end # module SportDb
