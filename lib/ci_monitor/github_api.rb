# frozen_string_literal: true

require 'jwt'
require 'net/http'
require 'octokit'
require 'openssl'

module CIMonitor
  module GithubAPI
    class Error < StandardError; end

    TOKEN_TTL = 50 * 60
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10
    BRANCH_CAP = 100
    @token_cache = {}
    @token_mutex = Mutex.new

    def self.clear_token_cache
      @token_mutex.synchronize { @token_cache = {} }
    end

    def self.exchange_code_for_token(code)
      uri = URI('https://github.com/login/oauth/access_token')
      params = URI.encode_www_form(
        client_id:     ENV.fetch('CI_MONITOR_GITHUB_APP_CLIENT_ID'),
        client_secret: ENV.fetch('CI_MONITOR_GITHUB_APP_CLIENT_SECRET'),
        code:          code
      )
      response = Net::HTTP.start(
        uri.host, uri.port,
        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT, use_ssl: true
      ) { |http| http.post(uri.path, params) }
      parsed = URI.decode_www_form(response.body).to_h
      raise Error, parsed['error_description'] || parsed['error'] if parsed.key?('error')

      parsed.fetch('access_token')
    end

    def self.user_installations(oauth_token)
      client = build_client(access_token: oauth_token)
      client.find_user_installations[:installations].map do |i|
        { app_id: i[:app_id], id: i[:id], account_login: i[:account][:login] }
      end
    rescue Octokit::Error => e
      raise Error, e.message
    end

    def self.installation_account(installation_id)
      client = build_client(bearer_token: app_jwt)
      installation = client.installation(installation_id)
      installation[:account][:login]
    rescue Octokit::Error
      nil
    end

    def self.installation_repos(installation_id)
      with_retry(installation_id) do |client|
        client.list_app_installation_repositories[:repositories].map do |r|
          { id: r[:id], full_name: r[:full_name], default_branch: r[:default_branch] || 'main' }
        end
      end
    rescue Octokit::Error => e
      raise Error, e.message
    end

    def self.repo_branches(installation_id, full_name)
      with_retry(installation_id) { |client| client.branches(full_name) }
        .first(BRANCH_CAP)
        .map { |b| { name: b[:name], commit: { sha: b[:commit][:sha] } } }
    rescue Octokit::Error => e
      raise Error, e.message
    end

    def self.commit_date(installation_id, full_name, sha)
      commit = with_retry(installation_id) { |client| client.commit(full_name, sha) }
      Time.parse(commit[:commit][:committer][:date].to_s)
    rescue Octokit::Error
      nil
    end

    def self.default_branch_commits(installation_id, full_name, branch, since:)
      with_retry(installation_id) do |client|
        client.commits(full_name, sha: branch, since: since.iso8601).map do |c|
          { sha: c[:sha], date: Time.parse(c[:commit][:committer][:date].to_s) }
        end
      end
    rescue Octokit::Error
      []
    end

    def self.merged_pulls(installation_id, full_name, since:)
      with_retry(installation_id) do |client|
        client.pull_requests(full_name, state: 'closed', sort: 'updated', direction: 'desc')
          .select { |pr| pr[:merged_at] && Time.parse(pr[:merged_at].to_s) >= since }
          .map { |pr| { branch: pr[:head][:ref], merged_at: Time.parse(pr[:merged_at].to_s) } }
      end
    rescue Octokit::Error
      []
    end

    def self.with_retry(installation_id)
      client = installation_client(installation_id)
      yield client
    rescue Octokit::Unauthorized
      evict_token(installation_id)
      client = installation_client(installation_id)
      yield client
    end

    def self.evict_token(installation_id)
      @token_mutex.synchronize { @token_cache.delete(installation_id) }
    end

    def self.installation_client(installation_id)
      @token_mutex.synchronize do
        cached = @token_cache[installation_id]
        return build_client(access_token: cached[:token]) if cached && cached[:expires_at] > Time.now

        app_client = build_client(bearer_token: app_jwt)
        token = app_client.create_app_installation_access_token(installation_id)[:token]
        @token_cache[installation_id] = { token: token, expires_at: Time.now + TOKEN_TTL }
        build_client(access_token: token)
      end
    end

    def self.build_client(**)
      client = Octokit::Client.new(
        **,
        connection_options: { request: { open_timeout: OPEN_TIMEOUT, timeout: READ_TIMEOUT } }
      )
      client.auto_paginate = true
      client
    end

    def self.app_jwt
      app_id = ENV.fetch('CI_MONITOR_GITHUB_APP_ID')
      raw = ENV.fetch('CI_MONITOR_GITHUB_PRIVATE_KEY')
      pem = raw.include?('BEGIN') ? raw : Base64.decode64(raw)
      private_key = OpenSSL::PKey::RSA.new(pem)
      payload = {
        iat: Time.now.to_i - 60,
        exp: Time.now.to_i + (10 * 60),
        iss: app_id
      }
      JWT.encode(payload, private_key, 'RS256')
    end

    private_class_method :installation_client, :build_client, :with_retry, :evict_token, :app_jwt
  end
end
