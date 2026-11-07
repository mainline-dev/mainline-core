# frozen_string_literal: true

require_relative '../model_spec_helper'
require_relative '../../lib/ci_monitor/github_api'
require 'concurrent'

describe 'CIMonitor::GithubAPI installation token caching' do
  before do
    ENV['CI_MONITOR_GITHUB_APP_ID'] = '12345'
    ENV['CI_MONITOR_GITHUB_PRIVATE_KEY'] = OpenSSL::PKey::RSA.generate(2048).to_pem
    CIMonitor::GithubAPI.clear_token_cache
  end

  it 'reuses cached token for same installation_id' do
    token_requests = 0
    fake_app_client = lambda {
      client = Minitest::Mock.new
      client.expect(:auto_paginate=, nil, [true])
      client.expect(:create_app_installation_access_token, { token: 'cached-token' }, [999])
      token_requests += 1
      client
    }

    fake_client = Minitest::Mock.new
    fake_client.expect(:auto_paginate=, nil, [true])
    fake_client.expect(:branches, [], ['acme/app'])
    fake_client.expect(:auto_paginate=, nil, [true])
    fake_client.expect(:branches, [], ['acme/app'])

    Octokit::Client.stub(:new, lambda { |**opts|
      opts[:bearer_token] ? fake_app_client.call : fake_client
    }) do
      CIMonitor::GithubAPI.repo_branches(999, 'acme/app')
      CIMonitor::GithubAPI.repo_branches(999, 'acme/app')
    end

    assert_equal 1, token_requests
  end
end

describe 'CIMonitor::GithubAPI.exchange_code_for_token' do
  before do
    ENV['CI_MONITOR_GITHUB_APP_CLIENT_ID'] = 'test-client-id'
    ENV['CI_MONITOR_GITHUB_APP_CLIENT_SECRET'] = 'test-client-secret'
  end

  it 'exchanges code for access token' do
    stub_response = { 'access_token' => 'ghu_abc123', 'token_type' => 'bearer' }
    http_stub = lambda { |_host, _port, **_opts, &block|
      http = Minitest::Mock.new
      response = Minitest::Mock.new
      response.expect(:body, URI.encode_www_form(stub_response))
      http.expect(:post, response, [String, String])
      block.call(http)
    }

    Net::HTTP.stub(:start, http_stub) do
      token = CIMonitor::GithubAPI.exchange_code_for_token('test-code')

      assert_equal 'ghu_abc123', token
    end
  end

  it 'raises Error when response has error field' do
    stub_response = { 'error' => 'bad_verification_code', 'error_description' => 'The code is invalid' }
    http_stub = lambda { |_host, _port, **_opts, &block|
      http = Minitest::Mock.new
      response = Minitest::Mock.new
      response.expect(:body, URI.encode_www_form(stub_response))
      http.expect(:post, response, [String, String])
      block.call(http)
    }

    Net::HTTP.stub(:start, http_stub) do
      assert_raises(CIMonitor::GithubAPI::Error) do
        CIMonitor::GithubAPI.exchange_code_for_token('bad-code')
      end
    end
  end

  it 'sets HTTP timeouts on token exchange' do
    captured_opts = nil
    Net::HTTP.stub(:start, lambda { |host, port, **opts, &block|
      captured_opts = opts.merge(host: host, port: port)
      http = Minitest::Mock.new
      response = Minitest::Mock.new
      response.expect(:body, URI.encode_www_form('access_token' => 'tok'))
      http.expect(:post, response, ['/login/oauth/access_token', String])
      block.call(http)
    }) do
      CIMonitor::GithubAPI.exchange_code_for_token('code')
    end

    assert_equal 'github.com', captured_opts[:host]
    assert_equal 443, captured_opts[:port]
    assert_equal 5, captured_opts[:open_timeout]
    assert_equal 10, captured_opts[:read_timeout]
    assert captured_opts[:use_ssl]
  end
end

describe 'CIMonitor::GithubAPI.repo_branches caps results' do
  before do
    ENV['CI_MONITOR_GITHUB_APP_ID'] = '12345'
    ENV['CI_MONITOR_GITHUB_PRIVATE_KEY'] = OpenSSL::PKey::RSA.generate(2048).to_pem
    CIMonitor::GithubAPI.clear_token_cache
  end

  it 'returns at most BRANCH_CAP branches' do
    many_branches = 150.times.map { |i|
      { name: "branch-#{i}", commit: { sha: "sha#{i}" } }
    }
    original_new = Octokit::Client.method(:new)

    Octokit::Client.stub(:new, lambda { |**opts|
      client = original_new.call(**opts)
      if opts[:bearer_token]
        def client.create_app_installation_access_token(_id)
          { token: 'tok' }
        end
      else
        client.define_singleton_method(:branches) { |_repo| many_branches }
      end
      client
    }) do
      result = CIMonitor::GithubAPI.repo_branches(111, 'acme/app')

      assert_operator result.size, :<=, CIMonitor::GithubAPI::BRANCH_CAP
    end
  end
end

describe 'CIMonitor::GithubAPI.commit_date error handling' do
  before do
    ENV['CI_MONITOR_GITHUB_APP_ID'] = '12345'
    ENV['CI_MONITOR_GITHUB_PRIVATE_KEY'] = OpenSSL::PKey::RSA.generate(2048).to_pem
    CIMonitor::GithubAPI.clear_token_cache
  end

  it 'returns nil instead of Time.now on API error' do
    Octokit::Client.stub(:new, lambda { |**opts|
      client = Minitest::Mock.new
      client.expect(:auto_paginate=, nil, [true])
      if opts[:bearer_token]
        client.expect(
          :create_app_installation_access_token, { token: 'tok' }, [111]
        )
      else
        def client.commit(_repo, _sha)
          resp = { status: 404, headers: {}, body: 'Not Found' }
          raise Octokit::NotFound.new(response_hash: resp)
        end
      end
      client
    }) do
      result = CIMonitor::GithubAPI.commit_date(111, 'acme/app', 'deadbeef')

      assert_nil result
    end
  end
end

describe 'CIMonitor::GithubAPI token cache invalidation on 401' do
  before do
    ENV['CI_MONITOR_GITHUB_APP_ID'] = '12345'
    ENV['CI_MONITOR_GITHUB_PRIVATE_KEY'] = OpenSSL::PKey::RSA.generate(2048).to_pem
    CIMonitor::GithubAPI.clear_token_cache
  end

  it 'evicts cached token and retries on Unauthorized' do
    token_requests = 0
    call_count = 0

    Octokit::Client.stub(:new, lambda { |**opts|
      client = Minitest::Mock.new
      client.expect(:auto_paginate=, nil, [true])
      if opts[:bearer_token]
        token_requests += 1
        client.expect(
          :create_app_installation_access_token, { token: "tok-#{token_requests}" }, [999]
        )
      else
        call_count += 1
        if call_count == 1
          def client.branches(_repo)
            resp = { status: 401, headers: {}, body: 'Bad credentials' }
            raise Octokit::Unauthorized.new(response_hash: resp)
          end
        else
          def client.branches(_repo)
            []
          end
        end
      end
      client
    }) do
      CIMonitor::GithubAPI.repo_branches(999, 'acme/app')
    end

    assert_equal 2, token_requests
  end
end

describe 'CIMonitor::GithubAPI token cache thread safety' do
  before do
    ENV['CI_MONITOR_GITHUB_APP_ID'] = '12345'
    ENV['CI_MONITOR_GITHUB_PRIVATE_KEY'] = OpenSSL::PKey::RSA.generate(2048).to_pem
    CIMonitor::GithubAPI.clear_token_cache
  end

  it 'synchronizes concurrent cache access with a mutex' do
    token_requests = Concurrent::AtomicFixnum.new(0)
    barrier = Concurrent::CyclicBarrier.new(4)

    Octokit::Client.stub(:new, lambda { |**opts|
      client = Minitest::Mock.new
      client.expect(:auto_paginate=, nil, [true])
      if opts[:bearer_token]
        client.expect(:create_app_installation_access_token, lambda { |_id|
          token_requests.increment
          sleep 0.01
          { token: "tok-#{token_requests.value}" }
        }, [777])
      else
        client.expect(:branches, [], ['acme/app'])
      end
      client
    }) do
      threads = 4.times.map {
        Thread.new do
          barrier.wait
          CIMonitor::GithubAPI.repo_branches(777, 'acme/app')
        end
      }
      threads.each(&:join)
    end

    assert_equal 1, token_requests.value
  end
end

describe 'CIMonitor::GithubAPI HTTP timeouts' do
  before do
    ENV['CI_MONITOR_GITHUB_APP_ID'] = '12345'
    ENV['CI_MONITOR_GITHUB_PRIVATE_KEY'] = OpenSSL::PKey::RSA.generate(2048).to_pem
    CIMonitor::GithubAPI.clear_token_cache
  end

  it 'configures Octokit clients with connection timeouts' do
    clients_created = []
    original_new = Octokit::Client.method(:new)

    Octokit::Client.stub(:new, lambda { |**opts|
      clients_created << opts
      client = original_new.call(**opts)
      if opts[:bearer_token]
        def client.create_app_installation_access_token(_id)
          { token: 'inst-token' }
        end
      else
        client.auto_paginate = true
        def client.branches(_repo)
          []
        end
      end
      client
    }) do
      CIMonitor::GithubAPI.repo_branches(888, 'acme/app')
    end

    inst_client = clients_created.find { |c| c[:access_token] == 'inst-token' }

    assert inst_client, 'installation client was not created'
    assert_equal 5, inst_client.dig(:connection_options, :request, :open_timeout)
    assert_equal 10, inst_client.dig(:connection_options, :request, :timeout)
  end
end
