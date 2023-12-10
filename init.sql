SELECT create_distributed_table('customers', 'customerid');
SELECT create_distributed_table('orders', 'customerid', colocate_with => 'customers');

SELECT citus_set_coordinator_host('coordinator', 5432);

-- add worker nodes to Citus metadata
SELECT citus_add_node('worker1', 5432);
SELECT citus_add_node('worker2', 5432);
SELECT citus_add_node('worker3', 5432);



SELECT rebalance_table_shards();
SELECT citus_drain_node('coordinator', 5432);
