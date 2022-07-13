require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "yaml"
require "date"
require "uri"
require 'street_address'
require 'fileutils'

configure do
  enable :sessions
  set :session_secret, "This is really secret"
end

helpers do
  def format_input(input)
    input = input.to_s.split('_')
    input.map(&:capitalize).join(' ')
  end

  def ordinalize(num)
    if (11..13).include?(num % 100)
      "#{num}th"
    else
      case num % 10
        when 1; "#{num}st"
        when 2; "#{num}nd"
        when 3; "#{num}rd"
        else    "#{num}th"
      end
    end
  end

  def format_values(key, value)
    case key
    when :date_of_birth
      "#{value.strftime("%B %d, %Y")}"
    when :training_schedule
      value = value.map { |day, time| "#{day}s at #{format_time_string(time)}" }
      join_and(value)
    when :additional_workouts
      join_and(value)
    else
        "#{value}"
    end
  end

  def format_time(time)
    time.strftime("%l:%M %p")
  end

  def format_time_string(time)
    Time.parse(time).strftime("%l:%M %p")
  end

  def join_and(arr)
    arr.map.with_index do |word, idx|
      case idx
      when (arr.size - 2)
        arr.size > 2 ? "#{word}, and" : "#{word} and"
      when (arr.size - 1)
        word
      else
        "#{word},"
      end
    end.join(' ')
  end

  def frequency_message(event)
    date = Date.parse(event[:date])

    case event[:frequency]
    when 'monthly'
      if date.day == 31
        "Repeats Every Month on the Final Day"
      else
        "Repeats Every Month on the #{ordinalize(date.day)}"
      end
    when 'quarterly'
      occurrences = occurrances(event[:date], event[:frequency])
      days = occurrences.map { |x| x.strftime("%-d") }
      occurrences.map!.with_index do |x, idx|
        x.strftime("%B #{ordinalize(days[idx])}")
      end
      occurrences = join_and(occurrences)
      "Repeats Quarterly on #{occurrences}"
    when 'annual'
      "Repeats Annualy on #{date.strftime("%B")} #{ordinalize(date.day)}"
    when 'once'
      "Occurs on #{date.strftime("%B %-d, %Y")}"
    end
  end
end

# File Paths

def current_clients
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/public/clients/current", __FILE__)
  else
    File.expand_path("../public/clients/current", __FILE__)
  end
end

def archived_clients
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/public/clients/archived", __FILE__)
  else
    File.expand_path("../public/clients/archived", __FILE__)
  end
end

def task_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/tasks_and_events/custom_tasks.yml", __FILE__)
  else
    File.expand_path("../tasks_and_events/custom_tasks.yml", __FILE__)
  end
end

def event_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/tasks_and_events/custom_events.yml", __FILE__)
  else
    File.expand_path("../tasks_and_events/custom_events.yml", __FILE__)
  end
end

# Convenience Methods

def days
  Date::DAYNAMES[1..-1] + [Date::DAYNAMES[0]]
end

def today
  Date.today.strftime("%A")
end

def tomorrow
  date = Date.today + 1
  date.strftime("%A")
end

def sorted_clients(path)
  Dir.children(path).sort
end

def this_week?(date)
  (Date.today..(Date.today + 7)).cover?(date_this_year(date))
end

def this_month?(date)
  next_month = Date.today + 30
  (Date.today..next_month).cover?(date_this_year(date))
end

def date_this_year(date)
  Date.parse([Date.today.year, date.month, date.day].join('-'))
end

# Locating, Parsing, and Validating Data

def data_paths(client_directory_path)
  client_names = sorted_clients(client_directory_path)

  client_names.map do |name|
    path = File.join(client_directory_path, name)
    File.join(path, 'data.yml')
  end
end

def parse_data(data_paths, value)
  data_paths.each_with_object({}) do |data_path, hsh|
    data = YAML.load_file(data_path)
    name = "#{data[:first_name]} #{data[:last_name]}"
    hsh[name] = data[value]
  end
end

def validate_client(data)
  errors = data.each_with_object([]) do |(key, value), arr|
    case key
    when :first_name, :last_name
      if value.empty? && !arr.include?("a complete name")
        arr << "a complete name"
      end
    when :date_of_birth
      if value.empty? || Date.today < Date.parse(value)
        arr << "a valid date of birth"
      end
    when :email
      unless value.match?(URI::MailTo::EMAIL_REGEXP)
        arr <<  "a valid email address"
      end
    when :address
      unless StreetAddress::US.parse(value)
        arr << "a street address containing the city, state, and street name and number"
      end
    end
  end

  errors = errors.sort_by { |x| x.size }
  "Please enter #{join_and(errors)}" unless errors.empty?
end

def validate_task(details)
  errors = details.each_with_object([]) do |(key, value), arr|
    next if key == :delete_on
    if value.nil? || value.empty?
      arr << "enter a task description" if key == :title
      arr << "set your task's schedule" if key == :schedule
      arr << "select a frequency" if key == :frequency
    end
  end

  "Please #{join_and(errors)}" unless errors.empty?
end

def validate_event(details)
  errors = details.each_with_object([]) do |(key, value), arr|
    if value.nil? || value.empty?
      arr << "enter an event description" if key == :title
      arr << "set your event's date" if key == :date
      arr << "select a frequency" if key == :frequency
    end
  end

  "Please #{join_and(errors)}" unless errors.empty?
end

def validate_file(file, filename)
  return "Please select a file" unless file
  "Filename can not be left blank" if filename.empty?
end

def format_client(data)
  data[:date_of_birth] = Date.parse(data[:date_of_birth])
  data[:training_schedule].delete_if { |_, v| v.empty? }
  data[:additional_workouts] ||= {}
  data[:additional_workouts] = data[:additional_workouts].keys

  data
end

# Managing Sessions

def successful_add(title, category)
  "You have successfully added #{title} to your #{category}"
end

def successful_delete(title, category)
  "You have successfully deleted #{title} from your #{category}"
end

def successful_move(name, category)
  "You have successfully moved #{name} to #{category}"
end

def successful_edit(name)
  "You have successfully edited #{name}'s data"
end

def successful_file_delete(filenames, client)
  file_string = join_and(filenames)
  name = format_input(client)
  "You have successfully deleted #{file_string} from #{name}'s Documents"
end

def configure_form(data)
  data.each do |key, value|
    if key == :training_schedule
      session[key] = value.values
    else
      session[key] = "#{value}"
    end
  end
end

# Birthdays

def birthdays_this_month
  data_paths = data_paths(current_clients) + data_paths(archived_clients)
  birthdays = parse_data(data_paths, :date_of_birth)

  birthdays.each_with_object({}) do |(name, date), hsh|
    if this_month?(date)
      hsh[date] ||= []
      hsh[date] << "#{name}'s birthday"
    end
  end.sort.to_h
end

def birthdays_this_week
  birthdays_this_month.select { |date, _| this_week?(date) }
end

# Training Schedule and Additional Workouts

  def todays_schedule
   data_paths = data_paths(current_clients)
   training_schedule = parse_data(data_paths, :training_schedule)

    training_schedule.each_with_object({}) do |(name, schedule), hsh|
      hsh[Time.parse(schedule[today])] = name if schedule.include?(today)
    end.sort.to_h
  end

  def weekly_workouts
    data_paths = data_paths(current_clients)
    additional_workouts = parse_data(data_paths, :additional_workouts)

    days.each_with_object({}) do |day, hsh|
      hsh[day] ||= []

      additional_workouts.each do |name, schedule|
        hsh[day] << name if schedule.include?(day)
      end
    end
  end

  def tomorrows_workouts
    workouts = weekly_workouts[tomorrow].map do |name|
      "Send tomorrow's workout to #{name}"
    end

    if tomorrow == "Saturday"
      workouts += weekly_workouts["Sunday"].map do |name|
        "Send Sunday's workout to #{name}"
      end
    end

    workouts
  end

# Custom Tasks

def weekly_custom_tasks
  tasks = YAML.load_file(task_path)
  return {} unless tasks

  tasks.each_with_object({}) do |task, hsh|
    task.each do |key, value|
      if expired?(task)
        delete_expired_tasks
        next
      elsif key == :schedule
        value.each do |day|
          hsh[day] ||= []
          hsh[day] << task[:title]
        end
      end
    end
  end
end

def todays_custom_tasks
  weekly_custom_tasks[today] || []
end

def tasks_this_week
  days = Date::DAYNAMES
  sorted_days = days[Date.today.wday..-1] + days[0...Date.today.wday]

  sorted_days.each_with_object({}) do |day, hsh|
    hsh[day] ||= []

    hsh[day] += weekly_custom_tasks[day] if weekly_custom_tasks.has_key?(day)

    unless weekly_workouts[day].empty?
      hsh[day] << "Client workouts due: #{join_and(weekly_workouts[day])}"
    end

    hsh[day] << "You have no tasks scheduled" if hsh[day].empty?
  end
end

def expired?(task)
  return false unless task[:delete_on]
  Date.today >= task[:delete_on]
end

def delete_expired_tasks
  tasks = YAML.load_file(task_path)

  tasks.reject! do |task|
    task[:delete_on] && task[:delete_on] <= Date.today
  end

  File.write(task_path, tasks.to_yaml)
end

def update_taskfile(task)
  custom_tasks = YAML.load_file(task_path)
  custom_tasks = [] unless custom_tasks
  custom_tasks << task
  File.write(task_path, custom_tasks.to_yaml)
end

def format_task(input)
  schedule = input.select { |_, v| v == 'on' }.keys
  task = {title: input[:task], schedule: schedule, frequency: input[:frequency]}
  task[:title].gsub!('"', "'")
  task[:delete_on] = (Date.today + 7) if input[:frequency] == "this_week"
  task
end

# Custom Events

def events_this_month
  events = YAML.load_file(event_path)
  return {} unless events

  events.each_with_object({}) do |event, hsh|
    occurrances(event[:date], event[:frequency]).each do |date|
      if this_month?(date)
        hsh[date] ||= []
        hsh[date] << event[:title]
      end
    end
  end.sort.to_h
end

def events_this_week
  events_this_month.select { |date, _| this_week?(date) }
end

def occurrances(date, frequency)
  day = Date.parse(date).day
  month = Date.parse(date).month
  result = []

  case frequency
  when 'monthly'
    1.upto(12) { |x| result << "#{day}/#{x}" }
  when 'quarterly'
    start = (1..12).select { |x| month % 3 == x }.min
    start ||= 3
    0.upto(3) { |x| result << "#{day}/#{start + (3 * x)}" }
  when 'annual'
    result << "#{day}/#{month}"
  when 'once'
    delete_expired_events
    return [Date.parse(date)]
  end

  result.map { |date| make_valid(date) }
end

def delete_expired_events
  events = YAML.load_file(event_path)

  events.reject! do |event|
    event[:frequency] == 'once' && Date.parse(event[:date]) < Date.today
  end

  File.write(event_path, events.to_yaml)
end

def make_valid(date)
  day, month = date.split('/').map(&:to_i)
  year = Date.today.year

  until Date.valid_date?(year, month, day)
    day -= 1
  end

  Date.new(year, month, day)
end

def update_eventfile(event)
  custom_events = YAML.load_file(event_path)
  custom_events = [] unless custom_events
  custom_events << event
  File.write(event_path, custom_events.to_yaml)
end

# Routes

# Displays the day's schedule, tasks, and events, and deletes yesterday's
# "completed tasks" from session data
get "/" do
  @title = "Dashboard"

  @tasks = todays_custom_tasks + tomorrows_workouts
  @events = birthdays_this_week.merge(events_this_week) do |key, new, old|
    new + old
  end.sort.to_h
  @schedule = todays_schedule


  @completed_tasks = session[:completed_tasks] ? session[:completed_tasks] : []
  @completed_tasks.delete_if { |_, v| v != Date.today }

  erb :index
end

# Displays alphabetically sorted lists of current and archived clients
get "/clients" do
  @title = "Clients"
  @current_clients = sorted_clients(current_clients)
  @archived_clients = sorted_clients(archived_clients)

  erb :clients
end

# Displays a specific client's document page
get "/:status/:client/documents" do
  @status = params[:status]
  group = @status == "current" ? current_clients : archived_clients

  @directory_name = params[:client]

  directory_path = File.join(group, @directory_name)
  path = File.join(directory_path, 'documents')

  @documents = Dir.children(path).sort
  @title = "#{format_input(@directory_name)}'s Documents"

  erb :documents
end

# Displays form for new client
get "/clients/new" do
  erb :new_client
end

# Displays all weekly tasks and events happening in the next month
get "/tasks_and_events" do
  @title = "Tasks and Events"
  @tasks = tasks_this_week
  @events = birthdays_this_month.merge(events_this_month) do |key, new, old|
    new + old
  end.sort.to_h

  erb :tasks
end

# Displays form for new task
get "/tasks/new" do
  erb :add_task
end

# Displays form for new event
get "/events/new" do
  erb :add_event
end

# Displays pre-populated form for editing client data
get "/edit/:name" do
  @directory_name = params[:name]

  @directory_path = File.join(current_clients, @directory_name)
  data_path = File.join(@directory_path, 'data.yml')

  @data = YAML.load_file(data_path)
  configure_form(@data)

  erb :edit_client
end

# Displays all tasks with the ability to delete them or create a new one
get "/tasks/edit" do
  @title = "Edit Tasks"
  @tasks = weekly_custom_tasks

  erb :edit_tasks
end

# Displays all events with the ability to delete them or create a new one
get "/events/edit" do
  @title = "Edit Events"
  events = YAML.load_file(event_path)
  @events = events ? events.sort_by { :title } : {}

  erb :edit_events
end

# Displays a document belonging to a client
get "/:status/:client/documents/:idx" do
  @status = params[:status]
  @client = params[:client]
  file_index = params[:idx].to_i

  group = @status == "current" ? current_clients : archived_clients
  directory_path = File.join(group, @client)
  documents_directory = File.join(directory_path, 'documents')

  @filename = Dir.children(documents_directory).sort[file_index]

  erb :view_document
end

# Displays data for specific client
get "/:status/:client" do
  @title = format_input(params[:client])
  @status = params[:status]
  group = @status == "current" ? current_clients : archived_clients

  @directory_name = params[:client]

  @directory_path = File.join(group, @directory_name)
  data_path = File.join(@directory_path, 'data.yml')

  @client_data = YAML.load_file(data_path)

  erb :client
end

# Formats "new task" form data, validates inputs, and adds the task to
# custom_tasks.yml
post "/new_task" do
  task = format_task(params)
  session[:error] = validate_task(task)

  if session[:error]
    configure_form(task)
    status 422
    erb :add_task
  else
    session[:success] = successful_add(task[:title], "Tasks")
    update_taskfile(task)

    redirect "/tasks/edit"
  end
end

# Formats "new event" form data, validates inputs, and adds the event to
# custom_events.yml
post "/new_event" do
  event = params.transform_keys(&:to_sym)
  event[:frequency] = params['frequency']
  session[:error] = validate_event(event)

  if session[:error]
    configure_form(event)
    status 422
    erb :add_event
  else
    session[:success] = successful_add(event[:title], "Events")
    update_eventfile(event)

    redirect "/events/edit"
  end
end

# Formats and validates inputs to "new client" form, creates new client
# directory containing data.yml and an empty documents directory
post "/new_client" do
  data = params.transform_keys(&:to_sym)
  session[:error] = validate_client(data)

  if session[:error]
    configure_form(data)
    status 422
    erb :new_client
  else
    directory_name = [data[:first_name], data[:last_name]].map do |name|
      name.downcase.split
    end.join("_")

    directory_path = File.join(current_clients, directory_name)
    name = format_input(directory_name)

    session[:success] = successful_add(name, "Current Clients")

    data = format_client(data)
    Dir.mkdir(directory_path)

    document_path = File.join(directory_path, 'documents')
    Dir.mkdir(document_path)

    data_path = File.join(directory_path, 'data.yml')
    File.write(data_path, data.to_yaml)

    redirect "/clients"
  end
end

# Formats and validates inputs to "edit client" form. If name has been changed,
# directory is renamed. Changes to client data are saved to :name/data.yml
post "/client/edit/:name" do
  data = params.transform_keys(&:to_sym)
  [:splat, :captures].each { |key| data.delete(key) }
  session[:error] = validate_client(data)

  if session[:error]
    configure_form(data)
    status 422
    erb :new_client
  else
    directory_name = [data[:first_name], data[:last_name]].map do |name|
      name.downcase.split
    end.join("_")

    directory_path = File.join(current_clients, directory_name)

    if directory_name != params[:name]
      old_directory_path = File.join(current_clients, params[:name])
      FileUtils.mv(old_directory_path, directory_path)
      FileUtils.rm_rf(old_directory_path)
    end

    data = format_client(data)

    data_path = File.join(directory_path, 'data.yml')
    File.write(data_path, data.to_yaml)
    session[:success] = successful_edit(format_input(directory_name))

    redirect "/clients"
  end
end

# Client directory is moved from Current to Archived
post "/archive/:name" do
  old_path = File.join(current_clients, params[:name])
  new_path = File.join(archived_clients, params[:name])

  FileUtils.mv(old_path, new_path)

  name = format_input(params[:name])
  session[:success] = successful_move(name, "Archived Clients")

  redirect "/clients"
end

# Client directory is moved from Archived to Current
post "/restore/:name" do
  old_path = File.join(archived_clients, params[:name])
  new_path = File.join(current_clients, params[:name])

  FileUtils.mv(old_path, new_path)

  name = format_input(params[:name])
  session[:success] = successful_move(name, "Current Clients")

  redirect "/clients"
end

# Client directory is deleted from Archive
post "/delete/:name" do
  path = File.join(archived_clients, params[:name])

  FileUtils.remove_dir(path)

  name = format_input(params[:name])
  session[:success] = successful_delete(name, "Archived Clients")

  redirect "/clients"
end

# Hash containing the day's completed tasks are stored in session
post "/complete/tasks" do
  session[:completed_tasks] = params.transform_values { Date.today }

  redirect "/"
end

# Tasks selected for deletion are removed from custom_tasks.yml
post "/tasks/delete" do
  deleted_tasks = params.transform_values(&:keys)
  tasks = YAML.load_file(task_path)

  tasks.each do |task|
    deleted_tasks.each do |day, titles|
      titles.each do |title|
        if task[:title] == title && task[:schedule].include?(day)
          task[:schedule].delete(day)
        end
      end
    end
  end

  tasks.reject! { |task| task[:schedule].empty? }

  message = join_and(deleted_tasks.values.flatten.uniq)
  session[:success] = successful_delete(message, "Tasks")

  File.write(task_path, tasks.to_yaml)

  redirect "/tasks/edit"
end

# Events selected for deletion are removed from custom_events.yml
post "/events/delete" do
  events = YAML.load_file(event_path)
  deleted_events = params.keys

  deleted_events.each do |deleted_event|
    events.delete_if { |event| event[:title] == deleted_event }
  end

  message = join_and(deleted_events)
  session[:success] = successful_delete(message, "Events")

  File.write(event_path, events.to_yaml)

  redirect "/events/edit"
end

#Validates, formats, and adds a file to client's documents
post "/:status/:client/documents/add" do
  @status = params[:status]
  group = @status == "current" ? current_clients : archived_clients

  file = params[:file][:tempfile]
  ext = File.extname(params[:file][:filename])
  filename = params[:filename]
  filename.gsub!(File.extname(filename), '')
  filename += ext

  client_path = File.join(group, params[:client])
  document_path = File.join(client_path, 'documents')
  file_path = File.join(document_path, filename)

  error_message = validate_file(params[:file], params[:filename])
  if error_message
    session[:error] = error_message
    redirect "/#{params[:status]}/#{params[:client]}/documents"
  else
    File.open(file_path, 'wb') do |f|
        f.write(file.read)
    end

    redirect "/#{params[:status]}/#{params[:client]}/documents"
  end
end

# Deletes selected files from client's documents
post "/:status/:client/documents/delete" do
  @status = params[:status]
  group = @status == "current" ? current_clients : archived_clients

  @deleted_files = params.select { |k,v| v == 'on' }.keys
  client_path = File.join(group, params[:client])
  document_path = File.join(client_path, 'documents')

  @deleted_files.each do |filename|
    file_path = File.join(document_path, filename)
    File.delete(file_path)
  end

  session[:success] = successful_file_delete(@deleted_files, params[:client])

  redirect "/#{params[:status]}/#{params[:client]}/documents"
end
