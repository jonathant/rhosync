module SourcesHelper
  
  def slog(e,msg,source_id,operation=nil,time=nil)
    begin
      p "Logging "+msg+ " for "+ source_id.to_s
      l=SourceLog.new
      l.source_id=source_id
      l.error=e.inspect.to_s if not e.nil?
      l.error||=""
      l.message=msg
      l.operation=operation
      l.time=time
      l.save
    rescue Exception=>e
      p "Failed to save source log message: " + e
    end
  end
  
  def tlog(start,operation,source_id)
    diff=(Time.new-start).round
    slog(nil,"Timing: "+diff.to_s+" seconds",source_id,operation,diff)
  end

  # determines if the logged in users is a subscriber of the current app or 
  # admin of the current app
  def check_access(app)
    p "checking access for user "+@current_user.login
    matches_login=app.users.select{ |u| u.login==@current_user.login}
    matches_login << app.administrations.select { |a| a.user.login==@current_user.login } # let the administrators of the app in as well
    if !(app.anonymous==1) and (matches_login.nil? or matches_login.size == 0)
      logger.info  "App is not anonymous and user was not found in subscriber list"
      logger.info "User: " + current_user.login + " not allowed access."
      username = current_user.login
      username ||= "unknown"
      result=nil
    end
    result=@current_user
  end
  
  def needs_refresh
    result=nil
    # refresh if there are any updates to come
    # INDEX: SHOULD USE BY_SOURCE_USER_TYPE 
    count_updates = "select count(*) from object_values where update_type!='query' and source_id="+id.to_s
    (count_updates << " and user_id="+ credential.user.id.to_s) if credential# if there is a credential then just do delete and update based upon the records with that credential  
    (result=true) if (ObjectValue.count_by_sql count_updates ) > 0

    # refresh if there is no data
    # INDEX: SHOULD USE BY_SOURCE_USER_TYPE
    count_query_objs="select count(*) from object_values where update_type='query' and source_id="+id.to_s
    (count_query_objs << " and user_id="+ credential.user.id.to_s) if credential# if there is a credential then just do delete and update based upon the records with that credential  
    (result=true) if (ObjectValue.count_by_sql count_query_objs ) <= 0
    
    # refresh is the data is old
    self.pollinterval||=300 # 5 minute default if there's no pollinterval or its a bad value
    if !self.refreshtime or ((Time.new - self.refreshtime)>pollinterval)
      result=true
    end
    result  # return true of false (nil)
  end
  
  # presence or absence of credential determines whether we are using a "per user sandbox" or not
  def clear_pending_records(credential)
    delete_cmd= "(update_type is null) and source_id="+id.to_s
    (delete_cmd << " and user_id="+ credential.user.id.to_s) if credential # if there is a credential then just do delete and update based upon the records with that credential
    ObjectValue.delete_all delete_cmd
  end
  
  # presence or absence of credential determines whether we are using a "per user sandbox" or not
  def remove_dupe_pendings(credential)
    pendings_cmd = "select id,pending_id,object,attrib,value from object_values where update_type is null and source_id="+id.to_s
    (pendings_cmd << " and user_id="+ credential.user.id.to_s) if credential# if there is a credential then just do delete and update based upon the records with that credential  
    pendings_cmd << " order by pending_id"
    objs=ObjectValue.find_by_sql pendings_cmd
    prev=nil
    objs.each do |obj|  # remove dupes
      if (prev and (obj.pending_id==prev.pending_id))
        p "Deleting a duplicate: " + obj.pending_id.to_s + "(#{obj.object.to_s},#{obj.attrib},#{obj.value})"
        ObjectValue.delete(prev.id)
      end
      prev=obj
    end
  end
  
  def update_pendings  
    conditions="source_id=#{id}"
    conditions << " and user_id=#{credential.user.id}" if credential
    objs=ObjectValue.find :all, :conditions=>conditions, :order=> :pending_id
    objs.each do |obj|  
      begin
        pending_to_query="update object_values set update_type='query',id=pending_id where id="+obj.id.to_s
        ActiveRecord::Base.connection.execute(pending_to_query)
      rescue Exception => e
        slog(e,"Failed to finalize object value (due to duplicate)",id)
      end
    end   
  end

  # presence or absence of credential determines whether we are using a "per user sandbox" or not
  def finalize_query_records(credential)
    # first delete the existing query records
    ActiveRecord::Base.transaction do
      delete_cmd = "(update_type is not null) and source_id="+id.to_s
      (delete_cmd << " and user_id="+ credential.user.id.to_s) if credential # if there is a credential then just do delete and update based upon the records with that credential
      ObjectValue.delete_all delete_cmd
=begin
      remove_dupe_pendings(credential)
      pending_to_query="update object_values set update_type='query',id=pending_id where update_type is null and source_id="+id.to_s
      (pending_to_query << " and user_id=" + credential.user.id.to_s) if credential
      ActiveRecord::Base.connection.execute(pending_to_query)
=end
      update_pendings
    end
    self.refreshtime=Time.new # timestamp    
  end

  # helper function to come up with the string used for the name_value_list
  # name_value_list =  [ { "name" => "name", "value" => "rhomobile" },
  #                     { "name" => "industry", "value" => "software" } ]
  def make_name_value_list(hash)
    if hash and hash.keys.size>0
      result="["
      hash.keys.each do |x|
        result << ("{'name' => '"+ x +"', 'value' => '" + hash[x] + "'},") if x and x.size>0 and hash[x]
      end
      result=result[0...result.size-1]  # chop off last comma
      result += "]"
    end
  end
    
  def process_update_type(utype)
    objs=ObjectValue.find_by_sql("select distinct(object) from object_values where update_type='"+ utype +"'and source_id="+id.to_s)
    objs.each do |x|
      if x.object  
        objvals=ObjectValue.find_all_by_object_and_update_type(x.object,utype)  # this has all the attribute value pairs now
        attrvalues={}
        attrvalues["id"]=x.object if utype!='create' # setting the ID allows it be an update or delete
        objvals.each do |y|
          attrvalues[y.attrib]=y.value
          y.destroy
        end
        # now attrvalues has the attribute values needed for the createcall
        nvlist=make_name_value_list(attrvalues)
        if source_adapter
          name_value_list=eval(nvlist)
          eval("source_adapter." +utype +"(name_value_list)")
        end
      else
        msg="Missing an object property on the objectvalue: " + x.id.to_s
        raise msg
        logger.info msg
      end
    end
  end
  
  def setup_client(client_id)
    # setup client & user association if it doesn't exist
    if client_id and client_id != 'client_id'
      @client = Client.find_by_client_id(client_id)
      if @client.nil?
        @client = Client.new
        @client.client_id = client_id
      end
      @client.user ||= current_user
      @client.save
    end
    @client
  end

  
  # creates an object_value list for a given client
  # based on that client's client_map records
  # and the current state of the object_values table
  # since we do a delete_all in rhosync refresh, 
  # only delete and insert are required
  def process_objects_for_client(source,client,token,p_size=nil,repeat=false)
    
    # default page size of 10000
    page_size = p_size.nil? ? 10000 : p_size.to_i
    last_sync_time = Time.now
    
    # Setup the join conditions
    object_value_join_conditions = "from object_values ov left join client_maps cm on \
                                    ov.id = cm.object_value_id and \
                                    cm.client_id = '#{client.id}'"
    object_value_conditions = "#{object_value_join_conditions} \
                               where ov.update_type = 'query' and \
                                 ov.source_id = #{source.id} and \
                                 (ov.user_id = #{current_user.id} or ov.user_id is NULL) and \
                                 cm.object_value_id is NULL order by ov.object limit #{page_size}"                  
    object_value_query = "select * #{object_value_conditions}"
    
    # setup fields to insert in client_maps table
    object_insert_query = "select '#{client.id}' as a,id,'insert','#{token}','#{last_sync_time.to_s}', \
                           '#{last_sync_time.to_s}' #{object_value_conditions}"
                    
    # received token: if we're repeating the show,
    # quickly return the results (inserts + deletes)
    if token and repeat
      objs_to_return = ObjectValue.get_delete_objs_by_token(token,page_size)
      client.update_attributes({:updated_at => last_sync_time, :last_sync_token => token})
      return objs_to_return.concat( ObjectValue.get_insert_objs_by_token(object_value_join_conditions,token,page_size) )
    end
    
    # no token, continue with processing
    # look for changes in the current object_values list, return only records
    # for the current user if required
    objs_to_return = []
    ActiveRecord::Base.transaction do
      dirty_flag = is_sqlite? ? "'f'" : 0
      objs_to_delete = ClientMap.find_by_sql "select * from client_maps cm left join object_values ov on \
                                              cm.object_value_id = ov.id \
                                              where cm.client_id='#{client.id}' and ov.id is NULL \
                                              and cm.dirty =#{dirty_flag} order by ov.object limit #{page_size}"
      objs_to_delete.each do |map|
        objs_to_return << ObjectValue.new_delete_obj(map.object_value_id)
        # update this client_map record with a dirty flag and the token, 
        # so we don't send it more than once
        dirty_flag = is_sqlite? ? "'t'" : 1
        ActiveRecord::Base.connection.execute "update client_maps set db_operation='delete',token='#{token}',dirty=#{dirty_flag} where \
                                               object_value_id='#{map.object_value_id}' \
                                               and client_id='#{map.client_id}'"
      end
    end
    
    # INDEX: BY_SOURCE_TYPE_USER
    objs_to_insert = ObjectValue.find_by_sql object_value_query
    
    # Add insert objects to client_maps based on 
    # join query w/ object_values
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute "insert into client_maps 
                                             (client_id,object_value_id,db_operation,token,created_at,updated_at) \
                                             #{object_insert_query}"                                      
    end
    
    # Update the last updated time for this client
    # to track the last sync time
    client.update_attribute(:updated_at, last_sync_time)
    
    # Setup return list (inserts + deletes)
    objs_to_insert.collect! {|x| x.db_operation = 'insert'; x}
    objs_to_return.concat(objs_to_insert)
  end
  
  private
  def is_sqlite?
    ActiveRecord::Base.connection.class.to_s =~ /SQLite3Adapter/
  end
end