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
  
    get "tasks_and_events"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Test Event"
    assert_includes last_response.body, "Test Task"
  end
end