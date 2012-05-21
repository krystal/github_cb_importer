#!/usr/local/env ruby

## Imports GitHub Tickets into Codebase Tickets

require 'json'
require 'net/http'

CODEBASE_USERNAME = '' 	## Codebase API username from profile page
CODEBASE_API_KEY  = '' 	## Codebase API key from profile page
GITHUB_USERNAME =  '' 	## Username for GitHub account
GITHUB_PASSWORD = ''	## Password for GitHub account
GITHUB_PROJECT = ''		## Repository name

GITHUB_USERS = {}
GITHUB_MILESTONE_CODEBASE_IDS = {};

def run_import

	if [CODEBASE_USERNAME, CODEBASE_API_KEY, GITHUB_USERNAME, GITHUB_PASSWORD, GITHUB_PROJECT].any? { |c| c.empty? }
	puts "Please edit the script to include your Codebase and GitHub credentials"
	exit 1
	end

	codebase_users = codebase_request('/users')
	github_project = github_request("")
	return unless github_project
	
	codebase_project = codebase_request("/create_project", :post, {'project' => {'name' => github_project['name']}})
	return unless codebase_project
	codebase_permalink = codebase_project["project"]["permalink"]
	
	codebase_statuses = codebase_request("/#{codebase_permalink}/tickets/statuses")
	closed_status = codebase_statuses.select { |status| status['ticketing_status']['treat_as_closed'] }.first
	closed_status_id = closed_status['ticketing_status']['id']
	
	open_status = codebase_statuses.reject { |status| status['ticketing_status']['treat_as_closed'] }.first
	open_status_id = open_status['ticketing_status']['id']
	
	codebase_info = {:open_status_id => open_status_id, :closed_status_id => closed_status_id,
		:permalink => codebase_permalink}
	
	github_milestones = github_request("/milestones")
	
	for milestone in github_milestones
		codebase_milestone_id = create_codebase_milestone(milestone, codebase_info)
		if codebase_milestone_id
			GITHUB_MILESTONE_CODEBASE_IDS[milestone["number"]] = codebase_milestone_id
		end
	end
	
	issues_page = 1
	begin
		github_open_issues = github_request("/issues?state=open&page=#{issues_page}&per_page=100")
		for issue in github_open_issues
			create_codebase_ticket(issue, codebase_info)
		end
		issues_page += 1
	end while github_open_issues.length > 0
	
	issues_page = 1
	begin
		github_closed_issues = github_request("/issues?state=closed&page=#{issues_page}&per_page=100")
		for issue in github_closed_issues
			create_codebase_ticket(issue, codebase_info)
		end
		issues_page += 1
	end while github_closed_issues.length > 0
	
end

def create_codebase_ticket(issue, codebase_info)

	status_id = issue['state'] == 'closed' ? codebase_info[:closed_status_id] : codebase_info[:open_status_id]
	user = find_github_user(issue["user"]["login"])
	if user.is_a?(Hash)
		user_info = {:reporter_name => user[:name], :reporter_email => user[:email]}
	else
		user_info = {:reporter_id => user}
	end

	assignee_id = nil
	if issue["assignee"]
		assignee = find_github_user(issue["assignee"]["login"])
		assignee_id = (assignee.is_a?(Integer) ? assignee : nil)
	end
		
	milestone_id = nil
	if issue["milestone"]
		milestone_id = GITHUB_MILESTONE_CODEBASE_IDS[issue["milestone"]["number"]]
	end
	
	tags = ""
	if issue["labels"]
		tags = issue["labels"].map { |label| label["name"] }.join(' ')
	end
	
	codebase_payload = {:ticket => {:summary => issue["title"], :description => issue["body"],
		:created_at => issue["created_at"], :updated_at => issue["updated_at"], :ticket_id => issue["number"],
		:status_id => status_id, :assignee_id => assignee_id, :milestone_id => milestone_id, :tags => tags}.merge(user_info)}

	codebase_ticket = codebase_request("/#{codebase_info[:permalink]}/tickets", :post, codebase_payload)
	return unless codebase_ticket
	
	codebase_ticket_number = codebase_ticket["ticket"]["ticket_id"]
	comments_page = 1
	begin
		github_comments = github_request("/issues/#{issue["number"]}/comments?page=#{comments_page}&per_page=100")
		for comment in github_comments
		
			user = find_github_user(comment["user"]["login"])
			if user.is_a?(Hash)
				user_info = {:author_name => user[:name], :author_email => user[:email]}
			else
				user_info = {:user_id => user}
			end
		
			update_payload = {:ticket_note => {:content => comment["body"],
				:created_at => comment["created_at"], :updated_at => comment["updated_at"]}.merge(user_info)}
			codebase_update = codebase_request("/#{codebase_info[:permalink]}/tickets/#{codebase_ticket_number}/notes", :post, update_payload)
		end
		comments_page += 1
	end while github_comments.length > 0
		
end

def create_codebase_milestone(milestone, codebase_info)

	milestone_creator = find_github_user(milestone["creator"]["login"])
	unless milestone_creator.is_a?(Integer)
		milestone_creator = nil
	end
	
	codebase_payload = {:ticketing_milestone => {
		:name => milestone["title"],
		:start_at => milestone["created_at"],
		:deadline => milestone["due_on"],
		:description => milestone["description"],
		:status => milestone["state"],
		:responsible_user_id => milestone_creator
	}}
	
	codebase_milestone = codebase_request("/#{codebase_info[:permalink]}/milestones", :post, codebase_payload)
	return codebase_milestone["ticketing_milestone"]["id"]
	
end

def find_github_user(user_name)
	@codebase_users ||= codebase_request('/users')

	if GITHUB_USERS.include? user_name
		return GITHUB_USERS[user_name]
	end 
	
	github_user = github_request("/#{user_name}", :users)
	if github_user["email"]
		codebase_user = @codebase_users.select {|user| user["user"]["email_address"] == github_user["email"] }.first
		if codebase_user
			user = codebase_user["user"]["id"]
		else
			user = {:name => github_user["name"], :email => github_user["email"]}
		end
	else
		user = {:name => github_user["name"], :email => ""}
	end
	
	GITHUB_USERS[user_name] = user
	return user
end 

def codebase_request(path, type = :get, payload = nil)
	if type == :get
		req = Net::HTTP::Get.new(path)
	elsif type == :post
		req = Net::HTTP::Post.new(path)
	end

	req.basic_auth(CODEBASE_USERNAME, CODEBASE_API_KEY)
	req['Content-Type'] = 'application/json'
	req['Accept'] = 'application/json'

	if payload.respond_to?(:to_json)
		req.body = payload.to_json
		puts req.body
	end
	

	if ENV["DEVELOPMENT"]
		res = Net::HTTP.new("api3.codebase.dev", 80)
	else
		res = Net::HTTP.new("api3.codebasehq.com", 443)
		res.use_ssl = true
		res.verify_mode = OpenSSL::SSL::VERIFY_NONE
	end

	request(res, req)
end

def github_request(path, type=:repos)
	case type
	when :repos
		prefix_path = "/repos/#{GITHUB_USERNAME}/#{GITHUB_PROJECT}"
	when :users
		prefix_path = "/users"
	end
	path = prefix_path + path
	
	req = Net::HTTP::Get.new(path);
	req.basic_auth(GITHUB_USERNAME, GITHUB_PASSWORD)
	req['User-Agent'] = "CodebaseHQ Importer (http://www.codebasehq.com/)"

	res = Net::HTTP.new("api.github.com", 443)
	res.use_ssl = true
	res.verify_mode = OpenSSL::SSL::VERIFY_NONE

	request(res, req)
end

def request(res, req)
	puts "Requesting #{req.path}"
	case result = res.request(req)
	when Net::HTTPSuccess
		#json decode
		return JSON.parse(result.body)
	else
		puts result
		puts "Sorry, that request failed."
		puts result.body
		return false
	end
end

run_import