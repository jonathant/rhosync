require 'active_record/fixtures'


class LoadAllSource < ActiveRecord::Migration
  def self.up

    dir=File.dirname(__FILE__)
    p dir
    Fixtures.create_fixtures("../../test/fixtures", "sources")

  end

  def self.down
  end
end
