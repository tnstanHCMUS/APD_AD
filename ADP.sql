USE master
GO
IF DB_ID('APD_PHYSICALDES') IS NOT NULL
	DROP DATABASE APD_PHYSICALDES
GO

CREATE DATABASE APD_PHYSICALDES
GO

USE APD_PHYSICALDES

CREATE TABLE Customer --LƯU THÔNG TIN KHÁCH HÀNG
(
	Customer_Identifier CHAR(10), --INDENTIFIER
    Customer_TelephoneNumber CHAR(10),
    Customer_Name NVARCHAR(50),
    Customer_Address NVARCHAR(30),
    Customer_City NVARCHAR(30),
    Customer_State NVARCHAR(30),
    Customer_ZipCode CHAR(10),
    Customer_CreditRating CHAR(10), --EXCELLENT/ GOOD/ FAIR/ POOR: ĐIỂM TÍN DỤNG

    CONSTRAINT PK_Customer
    PRIMARY KEY (Customer_Identifier)
)

CREATE TABLE Credit_Card --LƯU THÔNG TIN THẺ TÍN DỤNG CỦA KHÁCH HÀNG
(   
    Customer_CreditCard_Number CHAR(20), --INDENTIFIER
    Customer_CreditCard_Name NVARCHAR(50), --NAPAS/ DEBIT VISA/ DEBIT MASTER/ CREDIT VISA/ CREDIT MASTER
    CustomerIdentifier CHAR(10), --FOREIGN KEY

    CONSTRAINT PK_Credit_Card
    PRIMARY KEY (Customer_CreditCard_Number),

    CONSTRAINT FK_Credit_Card_Customer
    FOREIGN KEY (CustomerIdentifier) REFERENCES Customer
)
--thêm thuộc tính Preferred để đánh dấu thẻ tín dụng ưa thích của khách hàng
ALTER TABLE Credit_Card
ADD Preferred BIT --1: PREFERRED, 0: NOT PREFERRED


CREATE TABLE Orders --LƯU THÔNG TIN ĐƠN HÀNG CỦA KHÁCH HÀNG
(
    Order_Number CHAR(10),
    Customer_PhoneNumber CHAR(10),
    Customer_Identifier CHAR(10),
    OrderDate DATE,
    Shipping_Address NVARCHAR(30),
    Shipping_City NVARCHAR(30),
    Shipping_State NVARCHAR(30),
    Shipping_ZipCode CHAR(10),
    Customer_CreditCard_Number CHAR(20),
    Shipping_Date DATE,
    --derived attribute
    TotalCost FLOAT,

    CONSTRAINT PK_Orders
    PRIMARY KEY (Order_Number),

    CONSTRAINT FK_Orders_Credit_Card
    FOREIGN KEY (Customer_CreditCard_Number)
    REFERENCES Credit_Card,

    CONSTRAINT FK_Orders__Customer
    FOREIGN KEY (Customer_Identifier)
    REFERENCES Customer,
)

CREATE TABLE Advertised_Item
( 
    Item_Number CHAR(10),
    Item_Description NVARCHAR(100),
    Item_Department NVARCHAR(20),
    Item_Weight FLOAT,
    Item_Color NVARCHAR(10),
    Item_Price FLOAT,

    CONSTRAINT PK_Advertised_Item
    PRIMARY KEY (Item_Number)
)

CREATE TABLE Supplier
(   
    Supplier_ID CHAR(10),
    Supplier_Name NVARCHAR(20),
    Supplier_Address NVARCHAR(30),
    Supplier_City NVARCHAR(30),
    Supplier_State NVARCHAR(30),
    Supplier_ZipCode CHAR(10),

    CONSTRAINT PK_Supplier
    PRIMARY KEY (Supplier_ID)
)

CREATE TABLE Order_Item
(
    Item_Number CHAR(10),
    Order_Number CHAR(10),
    Quantity_Ordered TINYINT, --SỐ LƯỢNG ĐẶT HÀNG
    Selling_Price FLOAT, --GIÁ BÁN
    Shipping_Date DATE,

    CONSTRAINT PK_Ordered_Item
    PRIMARY KEY (Item_Number, Order_Number),

    CONSTRAINT FK_Ordered_Item_Order
    FOREIGN KEY (Order_Number)
    REFERENCES Orders,

    CONSTRAINT FK_Ordered_Item_Advertised_Item
    FOREIGN KEY (Item_Number)
    REFERENCES Advertised_Item,
)

CREATE TABLE Restock_Item
(
    Item_Number CHAR(10),
    Supplier_ID CHAR(10),
    Purchase_Price FLOAT, --GIÁ MUA

    CONSTRAINT PK_Restock_Item
    PRIMARY KEY (Item_Number, Supplier_ID),

    CONSTRAINT FK_Restock_Item_Advertised_Item
    FOREIGN KEY (Item_Number)
    REFERENCES Advertised_Item,

    CONSTRAINT FK_Restock_Item_Supplier
    FOREIGN KEY (Supplier_ID)
    REFERENCES Supplier,
)
GO



--B. INTEGITY CONSTRAINT
--1. Tổng chi phí của một đơn hàng phải bằng tổng giá trị của tất cả các mặt hàng trong đơn hàng.
CREATE TRIGGER TR_TOTAL_COST
ON Order_Item
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    -- Cập nhật lại tổng chi phí cho đơn hàng sau khi có sự thay đổi
    UPDATE O
    SET O.TotalCost = (
        SELECT SUM(I.Quantity_Ordered * I.Selling_Price)
        FROM Order_Item I
        WHERE I.Order_Number = O.Order_Number
        GROUP BY I.Order_Number
    )
    FROM Orders O
    JOIN (
        -- Lấy tất cả các đơn hàng bị ảnh hưởng bởi thao tác INSERT, UPDATE hoặc DELETE
        SELECT DISTINCT Order_Number 
        FROM INSERTED
        UNION
        SELECT DISTINCT Order_Number 
        FROM DELETED
    ) AS A ON O.Order_Number = A.Order_Number;
END;
GO

--2. Cập nhật customerID cho bảng Credit_Card khi có insert vào Orders
CREATE TRIGGER TR_CUSTOMER_ID
ON Orders
AFTER INSERT
AS
BEGIN
    -- Kiểm tra xem Customer_Identifier có tồn tại trong bảng Customer hay không
    IF NOT EXISTS (SELECT * FROM Customer WHERE Customer_Identifier IN (SELECT Customer_Identifier FROM INSERTED))
    BEGIN
        RAISERROR('Customer Identifier not found in Customer table', 16, 1);
        RETURN;
    END

    -- Kiểm tra xem Customer_CreditCard_Number đã được gán cho khách hàng khác chưa
    IF EXISTS (
        SELECT 1 
        FROM Credit_Card C
        JOIN INSERTED I ON C.Customer_CreditCard_Number = I.Customer_CreditCard_Number
        WHERE C.CustomerIdentifier IS NOT NULL AND C.CustomerIdentifier != I.Customer_Identifier
    )
    BEGIN
        RAISERROR('Credit Card has been used by another customer', 16, 1);
        RETURN;
    END
    
    --Nếu CusID trong Credit_Card và Orders giống nhau thì không làm gì
    IF EXISTS (
        SELECT 1 
        FROM Credit_Card C
        JOIN INSERTED I ON C.Customer_CreditCard_Number = I.Customer_CreditCard_Number
        WHERE C.CustomerIdentifier = I.Customer_Identifier
    )
    RETURN;
    -- Cập nhật CustomerIdentifier cho Credit_Card sau khi kiểm tra NULL
    UPDATE C
    SET C.CustomerIdentifier = I.Customer_Identifier
    FROM Credit_Card C
    JOIN INSERTED I ON C.Customer_CreditCard_Number = I.Customer_CreditCard_Number;
END;
GO


--3. Giá Selling_Price phải bằng Item_Price của mặt hàng đó.
CREATE TRIGGER TR_SELLING_PRICE
ON Order_Item
AFTER INSERT, UPDATE
AS
BEGIN
    --nếu Selling_Price không bằng Item_Price thì không thực hiện
    IF NOT EXISTS (SELECT * FROM Advertised_Item WHERE Item_Price = (SELECT Selling_Price FROM INSERTED))
        RAISERROR('Selling Price must be equal to Item Price', 16, 1);
END;
GO

--4. Mỗi khách hàng chỉ có 1 thẻ tín dụng được đánh dấu là Preferred (group by CustomerIdentifier)
CREATE TRIGGER TR_PREFERRED
ON Credit_Card
AFTER INSERT, UPDATE
AS
BEGIN
    --nếu có nhiều hơn 1 thẻ tín dụng được đánh dấu là Preferred thì không thực hiện
    IF (SELECT COUNT(*) FROM Credit_Card WHERE Preferred = 1 GROUP BY CustomerIdentifier) > 1
        RAISERROR('Only 1 Preferred Credit Card for each Customer', 16, 1);
END;
GO


/*select * from Orders
select * from Order_Item
select * from Advertised_Item
select * from Supplier
select * from Restock_Item
select * from Customer
select * from Credit_Card*/


--

--INDEXES 

--INSERT DATA





--SELECT QUERY
--1. Đối với một đơn đặt hàng của khách hàng cụ thể, tổng chi phí đơn hàng là bao nhiêu?
SELECT Order_Number, Customer_Identifier, TotalCost
FROM Orders
WHERE Order_Number = 'O0001'

--2. Đối với một sản phẩm quảng cáo cụ thể, giá thấp nhất mà nhà cung cấp hiện đang cung cấp là bao nhiêu?
SELECT A.Item_Number, A.Item_Description, A.Item_Department, A.Item_Weight, A.Item_Color, A.Item_Price, MIN(R.Purchase_Price) AS MinPurchasePrice
FROM Advertised_Item A JOIN Restock_Item R ON A.Item_Number = R.Item_Number
GROUP BY A.Item_Number, A.Item_Description, A.Item_Department, A.Item_Weight, A.Item_Color, A.Item_Price
--WHERE Item_Number = 'I0001'

--3. Khi thông tin khách hàng được truy xuất, bao gồm tất cả các số thẻ tín dụng của họ.
SELECT 
    C.Customer_Identifier, 
    C.Customer_TelephoneNumber, 
    C.Customer_Name, 
    C.Customer_Address, 
    C.Customer_City, 
    C.Customer_State, 
    C.Customer_ZipCode, 
    C.Customer_CreditRating, 
    CC.Customer_CreditCard_Number
FROM Customer C JOIN Credit_Card CC ON C.Customer_Identifier = CC.CustomerIdentifier
--WHERE C.CUSTOMER_IDENTIFIER = 'C0001'

--4. Giả định bổ sung thuộc tính PrederredOption vào bảng Credit_Card để quản lý thẻ tín dụng yêu thích của khách hàng. Khi thông tin khách hàng truy xuất, cho biết thông tin thẻ tín dụng yêu thích của họ.
SELECT 
    C.Customer_Identifier, 
    C.Customer_TelephoneNumber, 
    C.Customer_Name, 
    C.Customer_Address, 
    C.Customer_City, 
    C.Customer_State, 
    C.Customer_ZipCode, 
    C.Customer_CreditRating, 
    CC.Customer_CreditCard_Number, 
    CC.Preferred
FROM Customer C JOIN Credit_Card CC ON C.Customer_Identifier = CC.CustomerIdentifier
--WHERE C.CUSTOMER_IDENTIFIER = 'C0001'

--5. Cho biết thông tin khách hàng và số lần sử dụng trên mỗi thẻ tín dụng của họ.
SELECT 
    C.Customer_Identifier, 
    C.Customer_TelephoneNumber, 
    C.Customer_Name, 
    C.Customer_Address, 
    C.Customer_City, 
    C.Customer_State, 
    C.Customer_ZipCode, 
    C.Customer_CreditRating, 
    O.Customer_CreditCard_Number, 
    O.NumberOfUsage
FROM 
    Customer C
JOIN 
    (SELECT 
        O.Customer_Identifier, 
        O.Customer_CreditCard_Number, 
        COUNT(O.Customer_CreditCard_Number) AS NumberOfUsage
     FROM Orders O 
     GROUP BY O.Customer_Identifier, O.Customer_CreditCard_Number) AS O 
ON C.Customer_Identifier = O.Customer_Identifier



