# frozen_string_literal: true

Sequel.migration do
  up do
    run 'ALTER DEFAULT PRIVILEGES FOR ROLE mainline IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM mainline_app'
    run 'ALTER DEFAULT PRIVILEGES FOR ROLE mainline REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC'
    run <<~SQL
      DO $$
      DECLARE fn regprocedure;
      BEGIN
        FOR fn IN
          SELECT p.oid::regprocedure FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public'
             AND p.proowner = 'mainline'::regrole
             AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.deptype = 'e')
        LOOP
          EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, mainline_app', fn);
        END LOOP;
      END $$
    SQL
    run 'GRANT EXECUTE ON FUNCTION delete_team_data(uuid) TO mainline_app'
  end

  down do
    run 'ALTER DEFAULT PRIVILEGES FOR ROLE mainline GRANT EXECUTE ON FUNCTIONS TO PUBLIC'
    run 'ALTER DEFAULT PRIVILEGES FOR ROLE mainline IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO mainline_app'
    run 'GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO mainline_app, PUBLIC'
  end
end
