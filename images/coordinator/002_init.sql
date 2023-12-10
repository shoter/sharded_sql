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
