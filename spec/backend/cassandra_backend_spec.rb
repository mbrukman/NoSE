require 'nose/backend/cassandra'

module NoSE
  module Backend
    describe CassandraBackend do
      include_context 'dummy_cost_model'
      include_context 'entities'

      let(:backend) { CassandraBackend.new workload, [index], [], [], {} }

      it 'can generate DDL for a simple index' do
        expect(backend.indexes_ddl).to match_array [
          'CREATE COLUMNFAMILY "TweetIndex" ("User_Username" text, ' \
          '"Tweet_Timestamp" timestamp, "User_UserId" uuid, '\
          '"Tweet_TweetId" uuid, ' \
          '"Tweet_Body" text, PRIMARY KEY(("User_Username"), ' \
          '"Tweet_Timestamp", "User_UserId", "Tweet_TweetId"));'
        ]
      end

      it 'can lookup data for an index based on a plan' do
        # Materialize a view for the given query
        query = Statement.parse 'SELECT Tweet.Body FROM Tweet.User ' \
                                'WHERE User.Username = "Bob" ' \
                                'ORDER BY Tweet.Timestamp LIMIT 10',
                                workload.model
        index = query.materialize_view
        planner = Plans::QueryPlanner.new workload.model, [index], cost_model
        step = planner.min_plan(query).first

        # Validate the expected CQL query
        client = double('client')
        backend_query = 'SELECT User_Username, Tweet_Timestamp, Tweet_Body ' \
                        "FROM \"#{index.key}\" WHERE User_Username = ? " \
                        'ORDER BY Tweet_Timestamp LIMIT 10'
        expect(client).to receive(:prepare).with(backend_query) \
          .and_return(backend_query)

        # Define a simple array providing empty results
        results = []
        def results.last_page?
          true
        end
        expect(client).to receive(:execute) \
          .with(backend_query, arguments: ['Bob']).and_return(results)

        step_class = CassandraBackend::IndexLookupStatementStep
        prepared = step_class.new client, query.all_fields, query.conditions,
                                  step, nil, step.parent
        prepared.process query.conditions, nil
      end

      it 'can insert into an index' do
        client = double('client')
        index = link.simple_index
        values = [{
          'Link_LinkId' => nil,
          'Link_URL' => 'http://www.example.com/'
        }]
        backend_insert = "INSERT INTO #{index.key} (Link_LinkId, Link_URL) " \
                         'VALUES (?, ?)'
        expect(client).to receive(:prepare).with(backend_insert) \
          .and_return(backend_insert)
        expect(client).to receive(:execute) \
          .with(backend_insert, arguments: [kind_of(Cassandra::Uuid),
                'http://www.example.com/'])

        step_class = CassandraBackend::InsertStatementStep
        prepared = step_class.new client, index, [link['LinkId'], link['URL']]
        prepared.process values
      end
    end
  end
end
