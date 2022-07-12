ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"
require "yaml"

require_relative "../dashboard"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end
    
  def setup
    FileUtils.mkdir_p(current_clients)
    FileUtils.mkdir_p(archived_clients)
    File.write(task_path, '[]')
    File.write(event_path, '[]')
  end

  def teardown
    FileUtils.rm_rf("public")
    File.delete(task_path)
    File.delete(event_path)
  end
  
  def session
    last_request.env["rack.session"]
  end
  
  def add_task(title, schedule, frequency)
    task = {title: title, schedule: schedule, frequency: frequency}
    task[:delete_on] = (Date.today + 7) if frequency == "this_week"
    
    custom_tasks = YAML.load_file(task_path)
    custom_tasks << task
    File.write(task_path, custom_tasks.to_yaml)
  end
  
  def add_event(title, date, frequency)
    event = {title: title, date: date, frequency: frequency}
    
    custom_events = YAML.load_file(event_path)
    custom_events << event
    File.write(event_path, custom_events.to_yaml)
  end
  
  def add_client
    data = { first_name: "Test",
             last_name: "Client",
             address: "123 Fake St., Portland, OR",
             email: "test.email@testmail.com",
             phone: "555-666-7788",
             date_of_birth: Date.today - 365,
             training_schedule: { today => '13:00' },
             additional_workouts: [tomorrow]
            }
            
    directory_name = [data[:first_name], data[:last_name]].map do |name|
      name.downcase.split
    end.join("_")
    
    directory_path = File.join(current_clients, directory_name)
    Dir.mkdir(directory_path)
    
    document_path = File.join(directory_path, 'documents')
    Dir.mkdir(document_path)
    
    data_path = File.join(directory_path, 'data.yml')
    File.write(data_path, data.to_yaml)
  end
  
  def add_client_document
    directory_path = File.join(current_clients, 'test_client')
    document_path = File.join(directory_path, 'documents')
    file_path = File.join(document_path, 'test.txt')
    
    File.write(file_path, "This is a test document")
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
  
  def test_index_empty
    get "/"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You have no tasks today"
  end
  
  def test_index_tasks
    add_task("Test Task", [today], "every_week")
    
    get "/"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test Task"
  end
  
  def test_index_events
    add_event("Test Event", Date.today.to_s, "monthly")
    
    get "/"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test Event"
  end
  
  def test_index_birthday_and_schedule
    add_client
    
    get "/"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test Client's birthday on"
    assert_includes last_response.body, "<b> 1:00 PM</b>: Test Client"
  end

  def test_index_completed_tasks
    add_task("Test Task", [today], "every_week")
    
    get "/", {}, {"rack.session" => { completed_tasks: {"Test Task" => Date.today} }}
    assert_equal 200, last_response.status
    assert_includes last_response.body, "strikethrough"
  end
  
  def test_clients_empty
    get "clients"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You Have No Current Clients"
    assert_includes last_response.body, "You Have No Archived Clients"
  end
  
  def test_clients
    add_client
    
    get "clients"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test Client"
    assert_includes last_response.body, "You Have No Archived Clients"
  end
  
  def test_client_documents_empty
    add_client
    
    get "current/test_client/documents"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test Client Has No Saved Document"
  end
  
  def test_client_documents
    add_client
    add_client_document
    
    get "current/test_client/documents"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "test.txt"
  end
  
  def test_new_client
    get "clients/new"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Add Client"
  end
  
  def test_tasks_and_events_empty
    get "tasks_and_events"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You have no upcoming events"
    assert_includes last_response.body, "You have no tasks scheduled"
  end
  
  def test_tasks_and_events
    add_event("Test Event", Date.today.to_s, "monthly")
    add_task("Test Task", [today], "every_week")
    add_client
  
    get "tasks_and_events"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test Event"
    assert_includes last_response.body, "Test Task"
    assert_includes last_response.body, "Test Client"
  end
  
  def test_new_task
    get "/tasks/new"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Task Details"
    assert_includes last_response.body, "Perform on:"
    assert_includes last_response.body, "Frequency"
  end
  
  def test_new_event
    get "/events/new"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Event Details"
    assert_includes last_response.body, "Date"
    assert_includes last_response.body, "Frequency"
  end
  
  def test_edit_client
    add_client
    
    get "edit/test_client"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "123 Fake St., Portland, OR"
    assert_includes last_response.body, "test.email@testmail.com"
    assert_includes last_response.body, "555-666-7788"
  end
  
  def test_edit_tasks_empty
    get "/tasks/edit"
    assert_equal 200, last_response.status
    
    days.each do |day|
      assert_includes last_response.body, "You have no custom tasks scheduled on #{day}s"
    end
  end
  
  def test_edit_tasks
    add_task("Test Task", [today], "every_week")

    get "/tasks/edit"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test Task"
  end
  
  def test_edit_event_empty
    get "/events/edit"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You have no custom events scheduled"
  end
  
  def test_edit_event
    add_event("Test Event", Date.today.to_s, "monthly")
    dom = ordinalize(Date.today.day)
    
    
    get "/events/edit"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test Event"
    
    if dom == '31st'
      assert_includes last_response.body, "Repeats Every Month on the Final Day"
    else
      assert_includes last_response.body, "Repeats Every Month on the #{dom}"
    end
  end
  
  def test_document_display
    add_client
    add_client_document
  
    get "/current/test_client/documents/0"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "/clients/current/test_client/documents/test.txt"
  end
  
  def test_client_data
    add_client
    
    get "/current/test_client"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "123 Fake St., Portland, OR"
    assert_includes last_response.body, "test.email@testmail.com"
    assert_includes last_response.body, "555-666-7788"
  end
  
  def test_new_task
    get "/"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You have no tasks today"
    
    post "/new_task", {task: "Test Task", today: "on", frequency: "every_week"}, {}
    assert_equal 302, last_response.status
    assert_equal "You have successfully added Test Task to your Tasks", session[:success]
    
    get last_response["Location"] 
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test Task"
  end
  
  def test_new_task_error
    post "/new_task", {task: "Test Task", frequency: "every_week"}, {}
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Test Task"
    assert_includes last_response.body, "Please set your task's schedule"
  end
  
  def test_new_event
    get "/"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You have no events this week"
    
    post "/new_event", {title: "Test Event", date: Date.today.to_s, frequency: "monthly"}, {}
    assert_equal 302, last_response.status
    assert_equal "You have successfully added Test Event to your Events", session[:success]
    
    get last_response["Location"] 
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test Event"
  end
  
  def test_new_event_error
    post "/new_event", {title: "Test Event"}, {}
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Test Event"
    assert_includes last_response.body, "Please select a frequency"
  end
  
  def test_new_client
    data = { first_name: "Test",
             last_name: "Client",
             address: "123 Fake St., Portland, OR",
             email: "test.email@testmail.com",
             phone: "555-666-7788",
             date_of_birth: Date.today - 365,
             training_schedule: { today => '13:00' },
             additional_workouts: { tomorrow => "on" }
            }
    
    get "/clients"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You Have No Current Clients"
    
    post "/new_client", data, {}
    assert_equal 302, last_response.status
    assert_equal "You have successfully added Test Client to your Current Clients", session[:success]
    
    get last_response["Location"] 
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test Client"
  end
  
  def test_new_client_error
    data = { first_name: "Test",
             last_name: "Client",
             address: '',
             email: "test.email@testmail.com",
             phone: "555-666-7788",
             date_of_birth: '',
             training_schedule: { today => '13:00' },
             additional_workouts: { tomorrow => "on" }
            }
    
    post "/new_client", data, {}
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Test"
    assert_includes last_response.body, "Please enter a valid date of birth " \
    "and a street address containing the city, state, and street name and number"
  end
  
  def test_client_edit
    add_client
    
    new_data = { first_name: "New",
             last_name: "Client",
             address: '123 New Fake Rd. Portland, OR',
             email: "new.email@testmail.com",
             phone: "999-999-9999",
             date_of_birth: (Date.today - 365).to_s,
             training_schedule: { today => '13:00' },
             additional_workouts: { tomorrow => "on" }
            }
    
    post "/client/edit/test_client", new_data, {}
    assert_equal 302, last_response.status
    assert_equal "You have successfully edited New Client's data", session[:success]
  
    get last_response["Location"] 
    assert_equal 200, last_response.status
    assert_includes last_response.body, "New Client"
  end

  def test_client_edit
    add_client
    
    new_data = { first_name: "New",
             last_name: "Client",
             address: '',
             email: "new.email@testmail.com",
             phone: "999-999-9999",
             date_of_birth: '',
             training_schedule: { today => '13:00' },
             additional_workouts: { tomorrow => "on" }
            }
            
    post "/client/edit/test_client", new_data, {}
    assert_equal 422, last_response.status
    assert_includes last_response.body, "New"
    assert_includes last_response.body, "Please enter a valid date of birth " \
    "and a street address containing the city, state, and street name and number"
  end
  
  def test_archive_client
    add_client
    
    get '/clients'
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You Have No Archived Clients"
    
    post "archive/test_client"
    assert_equal 302, last_response.status
    assert_equal "You have successfully moved Test Client to Archived Clients", session[:success]
    
    get last_response["Location"] 
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You Have No Current Clients"
  end
  
  def test_restore_client
    add_client
    
    post "archive/test_client"
    assert_equal 302, last_response.status
    assert_equal "You have successfully moved Test Client to Archived Clients", session[:success]
    
    post "restore/test_client"
    assert_equal 302, last_response.status
    assert_equal "You have successfully moved Test Client to Current Clients", session[:success]
    
    get last_response["Location"] 
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You Have No Archived Clients"
  end
  
  def test_delete_client
    add_client
    
    get "/clients"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test Client"
    
    post "archive/test_client"
    post "/delete/test_client"
    assert_equal 302, last_response.status
    assert_equal "You have successfully deleted Test Client from your Archived Clients", session[:success]
    
    get last_response["Location"] 
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You Have No Current Clients"
  end
  
  def test_complete_tasks
    add_task("Test Task", [today], "every_week")
    
    post "/complete/tasks", { "Test Task" => Date.today }, {}
    assert_equal 302, last_response.status
    
    get last_response["Location"] 
    assert_equal 200, last_response.status
    assert_includes last_response.body, "strikethrough"
  end
  
  def test_delete_task
    add_task("Test Task", [today], "every_week")
    
    get "/tasks/edit"
    assert_includes last_response.body, "Test Task"
    
    post "/tasks/delete", { today => {"Test Task" => "on"} }, {}
    assert_equal 302, last_response.status
    assert_equal "You have successfully deleted Test Task from your Tasks", session[:success]
    
    get last_response["Location"] 
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You have no custom tasks scheduled on #{today}s"
  end
  
  def test_delete_event
    add_event("Test Event", Date.today.to_s, "monthly")
    
    get "/events/edit"
    assert_includes last_response.body, "Test Event"
    
    post "/events/delete", { "Test Event" => "on" }, {}
    assert_equal 302, last_response.status
    assert_equal "You have successfully deleted Test Event from your Events", session[:success]
    
    get last_response["Location"] 
    assert_equal 200, last_response.status
    assert_includes last_response.body, "You have no custom events scheduled"
  end
  
  def test_delete_file
    add_client
    add_client_document
    
    get "/current/test_client/documents"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "test.txt"
    
    post "/current/test_client/documents/delete", { "test.txt" => "on" }, {}
    assert_equal 302, last_response.status
    assert_equal "You have successfully deleted test.txt from Test Client's Documents", session[:success]
    
    get last_response["Location"] 
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test Client Has No Saved Documents"
  end
end