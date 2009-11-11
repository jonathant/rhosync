require 'redis'

class SyncStore
  attr_accessor :db

  def initialize
    @db = Redis.new
    raise "Error connecting to Redis store." unless @db and @db.is_a?(Redis)
  end
  
  # Adds set with given data, replaces existing set
  # if it exists
  def put_data(source,user_id,data={})
    if source and user_id
      key_prefix = _setkey_prefix(source,user_id)
      data.each do |key,value|
        value.each do |item|
          @db.sadd(_setkey(key_prefix,key),Marshal.dump(item))
        end
      end
    end
    true
  end
  
  # Retrieves set for given source,user
  def get_data(source,user_id)
    res = {}
    if source and user_id
      @db.keys("#{_setkey_prefix(source,user_id)}:*").each do |key|
        skey = key.split(':')[2]
        res[skey] = {}
        @db.smembers(key).each do |member|
          arr = Marshal.load(member)
          res[skey].merge!(arr[0] => arr[1])
        end
      end
      res
    end
  end
  
  private
  def _setkey_prefix(source,user_id)
    "#{source}:#{user_id.to_s}"
  end
  
  def _setkey(prefix,element)
    "#{prefix}:#{element.to_s}"
  end
end