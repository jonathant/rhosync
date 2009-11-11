require File.dirname(__FILE__) + "/../../../spec_helper"
require File.dirname(__FILE__) + "/sync_spec_helper"
require 'sync'

describe "sync store" do
  before do
    @source = 'Product'
    @user_id = 5
    
    @product1 = {
      'name' => 'iPhone',
      'brand' => 'Apple',
      'price' => '199.99'
    }
    
    @product2 = {
      'name' => 'G2',
      'brand' => 'Android',
      'price' => '99.99'
    }
    
    @data,@data['1'],@data['2'] = {},@product1,@product2
    
    @sync_store = SyncStore.new
    @sync_store.db.flushdb
  end
  
  it "should add simple data to new set" do
    pending("figure out runcoderun redis connectivity")
    @sync_store.put_data(@source,@user_id,@data).should == true
    @sync_store.get_data(@source,@user_id).should == @data
  end
  
  # it "should replace simple data to existing set" do
  #   new_data,new_data['3'] = {},{'name' => 'Droid','brand' => 'Google'}
  #   @sync_store.put_data(@source,@user_id,@data).should == true
  #   @sync_store.put_data(@source,@user_id,new_data)
  #   
  #   @sync_store.get_data(@source,@user_id).should == new_data
  # end
  # 
  # it "should compute diff between two sets" do
  #   
  # end
  # 
  # it "should compute intersect between two sets" do
  #   
  # end
  # 
  # it "should retrieve all keys for a set" do
  #   
  # end
  
end