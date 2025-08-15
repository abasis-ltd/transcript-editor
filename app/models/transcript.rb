class Transcript < ActiveRecord::Base

  include PgSearch
  multisearchable :against => [:title, :description]
  pg_search_scope :search_default, :against => [:title, :description]
  pg_search_scope :search_by_title, :against => :title

  validates_uniqueness_of :uid

  belongs_to :collection
  belongs_to :vendor
  belongs_to :transcript_status
  has_many :transcript_lines
  has_many :transcript_edits
  has_many :transcript_speakers

  def to_param
    uid
  end

  # ===================================================================
  # THE FIX IS HERE: The loadFromHash method has been updated
  # to handle both of your JSON formats.
  # ===================================================================
  def loadFromHash(contents)
    transcript_lines = []
    transcript_duration = 0
    vendor_audio_urls = []

    # --- Check for the "phrases" JSON format FIRST ---
    if contents.key?("phrases") && contents["phrases"].is_a?(Array)
      puts "  - Detected 'phrases' JSON format. Parsing..."
      raw_lines = contents["phrases"]
      
      raw_lines.each_with_index do |raw_line, i|
        # The data_cleanup.rake script should have already converted these to numbers
        start_time_ms = (raw_line["start_time"].to_f * 1000).to_i
        end_time_ms = (raw_line["end_time"].to_f * 1000).to_i

        transcript_lines << {
          transcript_id: id,
          start_time: start_time_ms,
          end_time: end_time_ms,
          original_text: raw_line["text"],
          text: raw_line["text"],
          sequence: i # This ensures sequence is never nil
        }
      end
      # Calculate duration from the last line
      last_line = raw_lines.last
      transcript_duration = last_line ? (last_line["end_time"].to_f).to_i : 0

    # --- Fallback to the original "audio_files" format ---
    elsif contents.key?("audio_files") && contents["audio_files"].is_a?(Array) && !contents["audio_files"].empty?
      puts "  - Detected 'audio_files' JSON format. Parsing..."
      audio_file_data = contents["audio_files"][0]
      
      if audio_file_data.dig("transcript", "parts")
        raw_lines = audio_file_data["transcript"]["parts"]
        raw_lines.each_with_index do |raw_line, i|
          transcript_lines << {
            transcript_id: id,
            start_time: (raw_line["start_time"].to_f * 1000).to_i,
            end_time: (raw_line["end_time"].to_f * 1000).to_i,
            original_text: raw_line["text"],
            text: raw_line["text"],
            sequence: i, # This ensures sequence is never nil
            speaker_id: raw_line["speaker_id"].to_i
          }
        end
      end
      
      transcript_duration = audio_file_data["duration"].to_i
      vendor_audio_urls = [audio_file_data["url"]].to_json
    end

    # --- Now, save the data if we found any lines ---
    if transcript_lines.any?
      # Use a transaction to ensure data integrity
      Transcript.transaction do
        # Destroy existing lines before inserting new ones
        TranscriptLine.where(transcript_id: id).destroy_all
        TranscriptLine.insert_all(transcript_lines)

        # Update the parent transcript
        completed_status = TranscriptStatus.find_by_name("completed")
        update!(
          lines: transcript_lines.length,
          transcript_status_id: completed_status&.id || self.transcript_status_id,
          duration: transcript_duration,
          vendor_audio_urls: vendor_audio_urls,
          transcript_retrieved_at: DateTime.now
        )
      end
      puts "  - SUCCESS: Created #{transcript_lines.length} lines for transcript #{uid}"

    else
      puts "  - WARNING: No valid lines found in the JSON for transcript #{uid}. It remains an empty shell."
    end
  end

  # ===================================================================
  # All other methods remain the same.
  # Only `loadFromHash` has been changed.
  # ===================================================================

  def self.getEdited
    Transcript.joins(:transcript_edits).distinct
  end

  def self.getByUserEdited(user_id)
    Transcript
      .joins(:transcript_edits)
      .where(transcript_edits: {user_id: user_id}).distinct
  end

  def self.getProjectTranscriptsUids(project_uid)
    Transcript
      .where(project_uid: project_uid)
  end

  def self.getForExport(project_uid, collection_uid=false)
    if collection_uid
      Transcript
        .select("transcripts.*, collections.uid AS collection_uid")
        .joins("INNER JOIN collections ON collections.id = transcripts.collection_id")
        .where("transcripts.lines > 0 AND transcripts.project_uid = :project_uid AND transcripts.is_published = :is_published AND collections.uid = :collection_uid", {project_uid: project_uid, is_published: 1, collection_uid: collection_uid})

    else
      Transcript
        .select("transcripts.*, COALESCE(collections.uid, \'\') as collection_uid")
        .joins("LEFT OUTER JOIN collections ON collections.id = transcripts.collection_id")
        .where("transcripts.lines > 0 AND transcripts.project_uid = :project_uid AND transcripts.is_published = :is_published", {project_uid: project_uid, is_published: 1})
    end
  end

  def self.getForHomepage(page=1, options={})
    page ||= 1
    options[:order] ||= "title"
    project = Project.getActive

    per_page = 500
    per_page = project[:data]["transcriptsPerPage"].to_i if project && project[:data]["transcriptsPerPage"]

    Rails.cache.fetch("#{ENV['PROJECT_ID']}/transcripts/#{page}/#{per_page}/#{options[:order]}", expires_in: 10.minutes) do
      Transcript
        .select('transcripts.*, COALESCE(collections.title, \'\') as collection_title')
        .joins('LEFT OUTER JOIN collections ON collections.id = transcripts.collection_id')
        .where("transcripts.lines > 0 AND transcripts.project_uid = :project_uid AND transcripts.is_published = :is_published AND transcripts.released = false", {project_uid: ENV['PROJECT_ID'], is_published: 1})
        .paginate(:page => page, :per_page => per_page).order("transcripts.#{options[:order]}")
    end
  end

  def self.getForDownloadByVendor(vendor_uid, project_uid)
    vendor = Vendor.find_by_uid(vendor_uid)
    Transcript.joins(:collection)
      .where("transcripts.vendor_id = :vendor_id AND transcripts.lines <= 0 AND transcripts.vendor_identifier != :empty AND transcripts.project_uid = :project_uid",
      {vendor_id: vendor[:id], empty: "", project_uid: project_uid})
  end

  def self.getForUpdateByVendor(vendor_uid, project_uid)
    vendor = Vendor.find_by_uid(vendor_uid)
    Transcript.joins(:collection)
      .where("transcripts.vendor_id = :vendor_id AND collections.vendor_id = :vendor_id AND collections.vendor_identifier != :empty AND transcripts.vendor_identifier != :empty AND transcripts.project_uid = :project_uid",
      {vendor_id: vendor[:id], empty: "", project_uid: project_uid})
  end

  def self.getForUploadByVendor(vendor_uid, project_uid)
    vendor = Vendor.find_by_uid(vendor_uid)
    Transcript.joins(:collection)
      .where("transcripts.vendor_id = :vendor_id AND transcripts.vendor_identifier = :empty AND collections.vendor_id = :vendor_id AND transcripts.lines <= 0 AND collections.vendor_identifier != :empty AND transcripts.project_uid = :project_uid",
      {vendor_id: vendor[:id], empty: "", project_uid: project_uid})
  end

  def self.getUpdatedAfter(date, page=1, options={})
    page ||= 1
    project = Project.getActive
    per_page = 500
    per_page = project[:data]["transcriptsPerPage"].to_i if project && project[:data]["transcriptsPerPage"]

    Transcript
      .select('transcripts.*, COALESCE(collections.uid, \'\') AS collection_uid')
      .joins('LEFT OUTER JOIN collections ON collections.id = transcripts.collection_id')
      .where("transcripts.lines > 0 AND transcripts.project_uid = :project_uid AND transcripts.is_published = :is_published AND transcripts.updated_at > :update_after", {project_uid: ENV['PROJECT_ID'], is_published: 1, update_after: date})
      .distinct
      .order("updated_at DESC")
      .paginate(:page => page, :per_page => per_page)
  end

  def self.sortableFields
    return ["percent_completed", "duration", "title", "collection_id"]
  end

  def delta(line_status_id_before, line_status_id_after, statuses=nil)
    return if lines <= 0
    statuses ||= TranscriptLineStatus.allCached
    changed = false
    new_lines_completed = lines_completed
    new_lines_edited = lines_edited
    new_lines_reviewing = lines_reviewing
    new_percent_completed = percent_completed
    new_percent_edited = percent_edited
    new_percent_reviewing = percent_reviewing
    before_status = statuses.find{|s| s[:id]==line_status_id_before}
    after_status = statuses.find{|s| s[:id]==line_status_id_after}
    if (!before_status || before_status.name!="editing") && after_status && after_status.name=="editing"
      new_lines_edited += 1
      changed = true
    elsif before_status && before_status.name=="editing" && (!after_status || after_status.name!="editing")
      new_lines_edited -= 1
      changed = true
    end
    if (!before_status || before_status.name!="completed") && after_status && after_status.name=="completed"
      new_lines_completed += 1
      changed = true
    elsif before_status && before_status.name=="completed" && (!after_status || after_status.name!="completed")
      new_lines_completed -= 1
      changed = true
    end
    if (!before_status || before_status.name!="reviewing") && after_status && after_status.name=="reviewing"
      new_lines_reviewing += 1
      changed = true
    elsif before_status && before_status.name=="reviewing" && (!after_status || after_status.name!="reviewing")
      new_lines_reviewing -= 1
      changed = true
    end
    if changed
      new_percent_edited = (1.0 * new_lines_edited / lines * 100).round.to_i
      new_percent_completed = (1.0 * new_lines_completed / lines * 100).round.to_i
      new_percent_reviewing = (1.0 * new_lines_reviewing / lines * 100).round.to_i
      update(lines_edited: new_lines_edited, lines_completed: new_lines_completed, lines_reviewing: new_lines_reviewing, percent_edited: new_percent_edited, percent_completed: new_percent_completed, percent_reviewing: new_percent_reviewing)
    end
  end

  def getUsersContributedCount(edits=[])
    if edits.length > 0
      edits.collect {|edit|
        if edit.user_id > 0
          edit.user_id.to_s
        else
          edit.session_id
        end
      }.uniq.length
    else
      TranscriptEdit
        .select("CASE WHEN user_id=0 THEN session_id ELSE to_char(user_id, '999999999999999') END")
        .where(transcript_id: id).distinct.count
    end
  end

  def loadFromWebVTT(webvtt)
    transcript_lines = _getLinesFromWebVTT(webvtt)
    if transcript_lines.length > 0
      TranscriptLine.where(transcript_id: id).destroy_all
      TranscriptLine.create(transcript_lines)
      transcript_status = TranscriptStatus.find_by_name("transcript_downloaded")
      transcript_duration = _getDurationFromWebVTT(webvtt)
      update(lines: transcript_lines.length,transcript_status_id: transcript_status[:id],duration: transcript_duration,transcript_retrieved_at: DateTime.now)
      puts "Created #{transcript_lines.length} lines from transcript #{uid}"
    end
    speaker_ids = TranscriptSpeaker.select("speaker_id").where(:transcript_id => id)
    speaker_ids = speaker_ids.map {|i| i.speaker_id }
    Speaker.where(id: speaker_ids).delete_all
    TranscriptSpeaker.where(transcript_id: id).destroy_all
    _getSpeakersWebVTT(webvtt)
  end

  def recalculate
    return if lines <= 0
    edited_lines = TranscriptLine.getEditedByTranscriptId(id)
    statuses = TranscriptLineStatus.allCached
    completed_status = statuses.find{|s| s[:name]=="completed"}
    completed_lines = edited_lines.select{|s| s[:transcript_line_status_id]==completed_status[:id]}
    reviewing_status = statuses.find{|s| s[:name]=="reviewing"}
    reviewing_lines = edited_lines.select{|s| s[:transcript_line_status_id]==reviewing_status[:id]}
    _lines_edited = edited_lines.length
    _lines_completed = completed_lines.length
    _lines_reviewing = reviewing_lines.length
    _percent_edited = (1.0 * _lines_edited / lines * 100).round.to_i
    _percent_completed = (1.0 * _lines_completed / lines * 100).round.to_i
    _percent_reviewing = (1.0 * _lines_reviewing / lines * 100).round.to_i
    _users_contributed = getUsersContributedCount()
    update(lines_edited: _lines_edited, lines_completed: _lines_completed, lines_reviewing: _lines_reviewing, percent_edited: _percent_edited, percent_completed: _percent_completed, percent_reviewing: _percent_reviewing, users_contributed: _users_contributed)
  end

  def self.search(options)
    options[:page] ||= 1
    project = Project.getActive
    per_page = 500
    per_page = project[:data]["transcriptsPerPage"].to_i if project && project[:data]["transcriptsPerPage"]
    sort_order = "ASC"
    sort_order = "DESC" if options[:order].present? && options[:order].downcase=="desc"
    options[:sort_by] ||= "title"
    sort_by = options[:sort_by]
    sort_by = "percent_completed" if sort_by.present? && sort_by=="completeness"
    sort_by = "title" if !Transcript.sortableFields().include? sort_by
    transcripts = nil
    transcripts = Transcript.select('transcripts.*, COALESCE(collections.title, \'\') as collection_title')
        .joins('LEFT OUTER JOIN collections ON collections.id = transcripts.collection_id')
        .where("transcripts.lines > 0 AND transcripts.project_uid = :project_uid AND transcripts.is_published = :is_published AND transcripts.released = false", {project_uid: ENV['PROJECT_ID'], is_published: 1})
    transcripts = transcripts.where("transcripts.collection_id = :collection_id", {collection_id: options[:collection_id].to_i}) if options[:collection_id].present?
    transcripts = transcripts.where("transcripts.title ILIKE '%#{options[:q]}%' OR transcripts.description ILIKE '%#{options[:q]}%'") if options[:q] && options[:q].present?
    transcripts.paginate(:page => options[:page], :per_page => per_page).order("transcripts.#{sort_by} #{sort_order}")
  end

  def updateFromHash(contents)
    vendor_audio_urls = _getAudioUrlsFromHash(contents)
    update(vendor_audio_urls: vendor_audio_urls)
  end

  def updateUsersContributed(edits=[])
    _users_contributed = getUsersContributedCount(edits)
    if _users_contributed != users_contributed
      update(users_contributed: _users_contributed)
    end
  end

  def _getDurationFromWebVTT(webvtt)
    duration = 0
    unless webvtt.cues.empty?
      duration = (webvtt.cues.last.end_in_sec).to_i
    end
    duration
  end

  def _getLinesFromWebVTT(webvtt)
    transcript_lines = []
    webvtt.cues.each_with_index do |cue, i|
      text = cue.text.gsub(/^<v [^>]*>[ ]*/, "")
      end_time = cue == webvtt.cues[-1] ? cue.end_in_sec : webvtt.cues[i + 1].start_in_sec
      transcript_lines << {
        :transcript_id => id,
        :start_time => (cue.start_in_sec * 1000).to_i,
        :end_time => (end_time * 1000).to_i,
        :original_text => text,
        :sequence => i
      }
    end
    transcript_lines
  end

  def _getSpeakersWebVTT(webvtt)
    speakers = []
    webvtt.cues.each_with_index do |cue, i|
      speakerMatch = /^<v ([^>]*)>[ ]*.*/.match(cue.text)
      unless speakerMatch.nil? || speakerMatch.captures.empty?
        speakerName = speakerMatch.captures.first
        speaker = speakers.find{|s| s[:name]==speakerName}
        if speaker.nil?
          speaker = Speaker.create(name: speakerName)
          TranscriptSpeaker.create(speaker_id: speaker.id, transcript_id: id, collection_id: collection_id, project_uid: project_uid)
          speakers << speaker
        end
        line = TranscriptLine.getByTranscriptSequence(id, i)
        if line && speaker
          line.update(speaker_id: speaker.id)
        end
      end
    end
  end

  def self.transcriptsCompleted(start_date=Time.new(2000,1,1), end_date=Time.now, page)
    transcriptQuery = Transcript.where("percent_completed >= 99").where('updated_at >= ?', start_date).where('updated_at <= ?', end_date)
    data = { total: transcriptQuery.count }
    transcripts = {}
    transcriptQuery.offset(page * 8).limit(8).each do |transcript|
      most_edits_user = nil
      transcript_completed_at = transcript.transcript_lines.order(updated_at: :desc).first.updated_at
      user_edit_counts = {}
      ts_user_ids = transcript.transcript_edits.select(:user_id).distinct.map(&:user_id)
      ts_user_ids.delete(0)
      ts_users = User.find( ts_user_ids )
      ts_users.each do |user|
        user_edit_counts[user.id] = transcript.transcript_edits.where(user_id: user.id).count
        next if user.id == 0
        if !most_edits_user || user_edit_counts[user.id] > user_edit_counts[most_edits_user.id]
          most_edits_user = user
        end
      end
      transcripts[transcript.uid] = {
        title: transcript.title,
        completed_at: transcript_completed_at,
        most_edits_user_email: most_edits_user.email,
        most_edits_user_count: user_edit_counts[most_edits_user.id]
      }
    end
    data[:transcripts] = transcripts
    data
  end

  def self.editActivity(start_date=Time.new(2000,1,1), end_date=Time.now, page)
    transcriptQuery = Transcript.where('updated_at >= ?', start_date).where('updated_at <= ?', end_date)
    data = { total: transcriptQuery.count }
    transcripts = {}
    transcriptQuery.offset(page * 8).limit(8).each do |transcript|
      if transcript.transcript_edits.count > 0
        lines_query = transcript.transcript_edits.where('created_at >= ?', start_date).where('created_at <= ?', end_date)
        new_edits_count = lines_query.count
        last_edit_date = lines_query.order(created_at: :desc).first.created_at.to_s
      else
        new_edits_count = 0
        last_edit_date = "N/A"
      end
      transcripts[transcript.uid] = { 
        title: transcript.title,
        edit_count: new_edits_count,
        last_edit_date: last_edit_date
      }
    end
    data[:transcripts] = transcripts
    data
  end

  def self.transcriptGraphData(start_date=Time.new(2000,1,1), division="month")
    data = {}
    data[:data] = []
    data[:labels] = []
    if division == "month"
      while start_date < Time.now
        data[:data] << TranscriptEdit.where('created_at >= ?', start_date).where('created_at <= ?', start_date + 1.month).count
        data[:labels] << "#{Date::MONTHNAMES[start_date.month]} #{start_date.year}"
        start_date = start_date + 1.month
      end
    end
    data    
  end
  
  def self.userGraphData(start_date=Time.new(2000,1,1), division="month")
    data = {}
    data[:data] = []
    data[:labels] = []
    if division == "month"
      while start_date < Time.now
        data[:data] << TranscriptEdit.where('created_at >= ?', start_date).where('created_at <= ?', start_date + 1.month).select(:user_id).distinct.count
        data[:labels] << "#{Date::MONTHNAMES[start_date.month]} #{start_date.year}"
        start_date = start_date + 1.month
      end
    end
    data
  end
end
