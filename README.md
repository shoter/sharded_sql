# Preface

I was wondering recently what one need to do in order to properly setup sharded SQL instances. 
I am writing this part of article before I begin my work on understanding how to setup such thing.

My plan is as follows:
- Use postgres SQL
- Have simple SQL schema which consists of 2 tables: `Customers` and `Orders`
- Each table has `CustomerId` column which is going to serve as a key for sharding SQL servers.
- Data for given customer should reside only on 1 specific instance of SQL servers
- I do not plan to write any C# code
- Everything needs to be dockerized and easy to setup

# Citus

I've learned from quick sweep of internet that currently default solution to sharding should be using Citus.  
This extension to pSQL was paid in the paid. In recent years it was made available for free so you can check out how you can do sharding without any expense.

# How to do sharding

Most of my knowledge on how to setup sharding is from this [citus article](https://www.citusdata.com/blog/2021/03/20/sharding-postgres-on-a-single-citus-node/).  
If you do not want to read step-by-step guide on how to set it up then you can just go to my [github repo with solution](https://github.com/shoter/sharded_sql)  

In order to do sharding you require coordinator pSQL server which is going to act as central management server for all of our shards.
It optionally can also serve as a shard itself if you want.  
Therefore we require 1 coordinator and X workers. In my case I am going to create 3 workers.

## Step-By-Step guide

1. Create a Dockerfile for your pSQL coordinator and initialization SQL.  
For some reason it is required to execute following SQL for your database or sharding might not work properly: `ALTER SYSTEM SET wal_level = logical;`

```SQL
CREATE TABLE Customers(
    CustomerID UUID PRIMARY KEY,
    Name TEXT);

CREATE TABLE Orders(
    CustomerID UUID,
    OrderID UUID,
    Name Text,
    OrderDate DATE,
    PRIMARY KEY (CustomerID, OrderID));

ALTER TABLE Orders ADD FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID);

INSERT INTO Customers (CustomerID, Name)
       SELECT gen_random_uuid(), 'Customer-' || i
       FROM generate_series(0, 1000) i;

INSERT INTO Orders (CustomerID, OrderID, Name, OrderDate)
    select CustomerId, gen_random_uuid(), 'Order-' || i, now()
    FROM Customers customer
    CROSS JOIN generate_series(0, 100) i;

ALTER SYSTEM SET wal_level = logical;
```

2. Create a dockerfile for your pSQL workers and add `ALTER SYSTEM SET wal_level = logical;` to them.

3. Create a definition of psql service for your coordinator:
```yml
services:
  coordinator:
    build:
      context: ../images/coordinator
    volumes:
      - coordinator_db:/var/lib/postgresql/data
    ports:
      - "12137:5432"
    environment:
      - POSTGRES_PASSWORD=shardpsql
volumes:
  coordinator_db:
  ```

4. And for your workers:
```yml
services:
  worker1:
    build:
      context: ../images/worker
    volumes:
      - worker1_db:/var/lib/postgresql/data
    ports:
      - "10001:5432"
    environment:
      - POSTGRES_PASSWORD=shardpsql
  worker2:
    build:
      context: ../images/worker
    volumes:
      - worker2_db:/var/lib/postgresql/data
    ports:
      - "10002:5432"
    environment:
      - POSTGRES_PASSWORD=shardpsql
  worker3:
    build:
      context: ../images/worker
    volumes:
      - worker3_db:/var/lib/postgresql/data
    ports:
      - "10003:5432"
    environment:
      - POSTGRES_PASSWORD=shardpsql

volumes:
  worker1_db:
  worker2_db:
  worker3_db:
```

5. After starting all of your services you need to execute SQL script on coordinator to enable partitioning on the tables you want:

```SQL
SELECT create_distributed_table('customers', 'customerid');
SELECT create_distributed_table('orders', 'customerid', colocate_with => 'customers');
```

By using `colocate_with` all orders tied to given customers are going to always stay within 1 shard.  
After executing this command our data is paritioned on coordinator node. It is not yet transferred to any nodes.

6. Now we need to inform the coordinator who is the coordinator and who is a citus node:

```SQL
SELECT citus_set_coordinator_host('coordinator', 5432);

-- add worker nodes to Citus metadata
SELECT citus_add_node('worker1', 5432);
SELECT citus_add_node('worker2', 5432);
SELECT citus_add_node('worker3', 5432);
```

7. After such operation we need to balance data between shards as all data currently resides on coordinator node:
```SQL
SELECT rebalance_table_shards();
```

8. If you want to remove data from your coordinator node you can always tell it so by executing following SQL:
```SQL
SELECT citus_drain_node('coordinator', 5432);
```

# Conclusion

Setting up sharding on pSQL server might be time consuming for the first time when you have 0 knowledge about the topic. It is not a hard task though and everyone should be able to do that.

It is a pity that I could not find an easy way to query data only from a given node.
Everytime I've queried data it was always coming from all nodes at once.  
At first i was not entirely sure if my data is properly paritioned. I've discovered [diagnostic queries](https://docs.citusdata.com/en/v11.1/admin_guide/diagnostic_queries.html) which proved that it is partitioned properly and is residing on different nodes.
