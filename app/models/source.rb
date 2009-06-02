class Source < ActiveRecord::Base
  include SourcesHelper
  has_many :object_values
  has_many :source_logs
  belongs_to :app
  attr_accessor :source_adapter,:current_user,:credential
  validates_presence_of :name,:adapter

  def before_validate
    self.initadapter
  end

  def before_save
    self.pollinterval||=300
    self.priority||=3
  end
  
  def to_param
    name.gsub(/[^a-z0-9]+/i, '-') unless new_record?
  end
  
  def self.find_by_permalink(link)
    Source.find(:first, :conditions => ["id =:link or name =:link", {:link=> link}])
  end
  
  def initadapter(credential)
    #create a source adapter with methods on it if there is a source adapter class identified
    if (credential and credential.url.blank?) and (!credential and self.url.blank?)
      msg= "Need to to have a URL for the source in either a user credential or globally"
      slog(nil,msg,self.id)
      raise msg
    end
    if not self.adapter.blank? 
      begin
        @source_adapter=(Object.const_get(self.adapter)).new(self,credential) 
      rescue
        msg="No such adapter class provided!"
        p msg
        slog(nil,msg)
      end
    else # if source_adapter is nil it will
      @source_adapter=nil
    end
  end
  
  def ask(current_user,question)
    usersub=app.memberships.find_by_user_id(current_user.id) if current_user
    self.credential=usersub.credential if usersub # this variable is available in your source adapter
    initadapter(self.credential)
    start=Time.new
    result=source_adapter.ask question
    tlog(start,"ask",self.id)
    result
  end
  
  def refresh(current_user)
    p "Queuesync: " + queuesync.to_s
    if  queuesync==true # queue up the sync/refresh task for processing by the daemon with doqueuedsync (below)
      task=Synctask.find_or_create_by_user_id_and_source_id(current_user.id,id)
      task.save
      p "Queued up task for user "+current_user.login+ ", source "+name
    else # go ahead and do it right now
      dosync(current_user)
    end
  end
  
  def self.doqueuedsync
    synctask=Synctask.find :first,:order=>:created_at
    source=Source.find synctask.source_id
    user=User.find synctask.user_id
    source.dosync(user)  # call the method below that performs the actual sync
    source.notify_users  # wake up the Rhodes clients to tell them to sync!
    synctask.delete  # take this task out of the queue
  end
  
  def notify_users

    ovs=ObjectValue.find(:all, :select=>"distinct(user_id) as user_id",:conditions=>{:source_id=>id})
    ovs.each do |ov|
      logger.debug "Notifying user: " + ov.user_id.to_s
      user=User.find ov.user_id
      user.notify # ping the user (Rhodes client) to tell them to sync
    end
  end

  def dosync(current_user)
    @current_user=current_user
    logger.info "Logged in as: "+ current_user.login if current_user
    
    usersub=app.memberships.find_by_user_id(current_user.id) if current_user
    self.credential=usersub.credential if usersub # this variable is available in your source adapter
    initadapter(self.credential)   
    # make sure to use @client and @session_id variable in your code that is edited into each source!
    begin
      start=Time.new
      source_adapter.login  # should set up @session_id
      tlog(start,"login",self.id)  # log how long it takes to do the login
    rescue Exception=>e
      logger.info "Failed to login"
      slog(e,"can't login",self.id,"login")
    end
    
    # first grab out all ObjectValues of updatetype="Create" with object named "qparms"
    # put those together into a qparms hash
    # qparms is nil or empty if there is no such hash
    qparms=qparms_from_object(current_user.id)
    # must do it before the create processing below!
    begin 
      process_update_type('create')
      cleanup_update_type('create')
    rescue Exception=>e
      slog(e, "Failed to create",self.id,"create")
      raise e
    end 

    begin
      process_update_type('update')
      cleanup_update_type('update')
    rescue Exception=>e
      slog(e, "Failed to update",self.id,"update")
      raise e
    end
    
    begin
      process_update_type('delete')
      cleanup_update_type('delete')
    rescue Exception=>e
      slog(e, "Failed to delete",self.id,"delete")
      raise e
    end
        
    clear_pending_records(@credential)

    begin  
      start=Time.new
      source_adapter.qparms=qparms if qparms  # note that we must have an attribute called qparms in the source adapter for this to work!
      source_adapter.query 
      tlog(start,"query",self.id)
    rescue Exception=>e
      p "Failed to perform query"
      slog(e,"timed out on query",self.id)
    end
    start=Time.new
    source_adapter.sync
    tlog(start,"sync",self.id)
    start=Time.new
    finalize_query_records(@credential)
    tlog(start,"finalize",self.id)
    source_adapter.logoff
    save
  end

end
