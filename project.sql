-- Drop database if exists and create new
DROP DATABASE IF EXISTS lib_mgmt;
CREATE DATABASE lib_mgmt;
USE lib_mgmt;

-- Create the Authors table
CREATE TABLE Authors (
    Author_ID INT PRIMARY KEY AUTO_INCREMENT,
    Author_Name VARCHAR(100) NOT NULL,
    Created_At TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY unique_author (Author_Name)
);

-- Create the Categories table
CREATE TABLE Categories (
    Category_ID INT PRIMARY KEY AUTO_INCREMENT,
    Category_Name VARCHAR(50) NOT NULL UNIQUE
);

-- Create the Books table
CREATE TABLE Books (
    ISBN VARCHAR(13) PRIMARY KEY,
    Title VARCHAR(255) NOT NULL,
    Author_ID INT,
    Category_ID INT,
    Availability ENUM('In stock', 'Checked out') NOT NULL DEFAULT 'In stock',
    Created_At TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    Updated_At TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (Author_ID) REFERENCES Authors(Author_ID) ON DELETE RESTRICT,
    FOREIGN KEY (Category_ID) REFERENCES Categories(Category_ID) ON DELETE RESTRICT
);

-- Create the Administrators table
CREATE TABLE Administrators (
    Admin_ID INT PRIMARY KEY AUTO_INCREMENT,
    Username VARCHAR(50) NOT NULL UNIQUE,
    Password VARCHAR(64) NOT NULL, -- For hashed passwords
    First_Name VARCHAR(50) NOT NULL,
    Last_Name VARCHAR(50) NOT NULL,
    Email VARCHAR(100) NOT NULL UNIQUE,
    Role ENUM('Super Admin', 'Admin', 'Librarian') NOT NULL,
    Created_At TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    Last_Login TIMESTAMP
);

-- Create the Members table
CREATE TABLE Members (
    Member_ID INT PRIMARY KEY AUTO_INCREMENT,
    Username VARCHAR(50) NOT NULL UNIQUE,
    Password VARCHAR(64) NOT NULL, -- For hashed passwords
    First_Name VARCHAR(50) NOT NULL,
    Last_Name VARCHAR(50) NOT NULL,
    Email VARCHAR(100) NOT NULL UNIQUE,
    Status ENUM('Active', 'Suspended', 'Expired') NOT NULL DEFAULT 'Active',
    Created_At TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    Last_Login TIMESTAMP
);

-- Create the Transactions table for tracking member borrowings
CREATE TABLE MemberTransactions (
    Transaction_ID INT PRIMARY KEY AUTO_INCREMENT,
    Member_ID INT NOT NULL,
    ISBN VARCHAR(13) NOT NULL,
    Transaction_Type ENUM('Borrow', 'Return') NOT NULL,
    Transaction_Date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    Due_Date DATE,
    Return_Date DATE,
    Fine_Amount DECIMAL(10, 2) DEFAULT 0.00,
    Status ENUM('Active', 'Completed', 'Overdue') DEFAULT 'Active',
    FOREIGN KEY (Member_ID) REFERENCES Members(Member_ID),
    FOREIGN KEY (ISBN) REFERENCES Books(ISBN)
);

-- Create the Transactions table for admin operations
CREATE TABLE AdminTransactions (
    Transaction_ID INT PRIMARY KEY AUTO_INCREMENT,
    ISBN VARCHAR(13) NOT NULL,
    Admin_ID INT NOT NULL,
    Transaction_Type ENUM('Check out', 'Return') NOT NULL,
    Transaction_Date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    Notes TEXT,
    FOREIGN KEY (ISBN) REFERENCES Books(ISBN),
    FOREIGN KEY (Admin_ID) REFERENCES Administrators(Admin_ID)
);

-- Insert sample categories
INSERT INTO Categories (Category_Name) VALUES
('Fiction'),
('Non-Fiction'),
('Science'),
('Technology'),
('Chemistry'),
('Physics'),
('Mechanics and Mechanical'),
('DBMS'),
('Programming'),
('Software Engineering'),
('Mathematics');

-- Insert sample administrators (password: admin123)
INSERT INTO Administrators (Username, Password, First_Name, Last_Name, Email, Role) VALUES
('admin', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'System', 'Admin', 'admin@library.com', 'Super Admin'),
('librarian', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'Head', 'Librarian', 'librarian@library.com', 'Librarian');

-- Insert sample authors
INSERT INTO Authors (Author_Name) VALUES
('George Orwell'),
('J.K. Rowling'),
('Stephen Hawking'),
('Aakanksh Seelin');

-- Insert sample books
INSERT INTO Books (ISBN, Title, Author_ID, Category_ID) VALUES
('9780451524935', '1984', 1, 1),
('9780439708180', 'Harry Potter and the Sorcerer''s Stone', 2, 1),
('9780553380163', 'A Brief History of Time', 3, 3);

-- Insert sample members (password: member123)
INSERT INTO Members (Username, Password, First_Name, Last_Name, Email, Status) VALUES
('john_doe', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'John', 'Doe', 'john.doe@email.com', 'Active'),
('jane_smith', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'Jane', 'Smith', 'jane.smith@email.com', 'Active');

-- Create procedure to check out a book (Admin)
DELIMITER //
CREATE PROCEDURE CheckOutBook(
    IN p_admin_id INT,
    IN p_isbn VARCHAR(13)
)
BEGIN
    DECLARE v_book_available BOOLEAN;

    -- Check if book is available
    SELECT Availability = 'In stock' INTO v_book_available
    FROM Books 
    WHERE ISBN = p_isbn;

    IF NOT v_book_available THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Book is not available for checkout';
    END IF;

    START TRANSACTION;

    -- Update book status
    UPDATE Books 
    SET Availability = 'Checked out'
    WHERE ISBN = p_isbn;

    -- Record admin transaction
    INSERT INTO AdminTransactions (ISBN, Admin_ID, Transaction_Type)
    VALUES (p_isbn, p_admin_id, 'Check out');

    COMMIT;
END //
DELIMITER ;

-- Create procedure to return a book (Admin)
DELIMITER //
CREATE PROCEDURE ReturnBook(
    IN p_admin_id INT,
    IN p_isbn VARCHAR(13)
)
BEGIN
    DECLARE v_book_checked_out BOOLEAN;

    -- Check if book is checked out
    SELECT Availability = 'Checked out' INTO v_book_checked_out
    FROM Books 
    WHERE ISBN = p_isbn;

    IF NOT v_book_checked_out THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Book is already in stock';
    END IF;

    START TRANSACTION;

    -- Update book status
    UPDATE Books 
    SET Availability = 'In stock'
    WHERE ISBN = p_isbn;

    -- Record admin transaction
    INSERT INTO AdminTransactions (ISBN, Admin_ID, Transaction_Type)
    VALUES (p_isbn, p_admin_id, 'Return');

    COMMIT;
END //
DELIMITER ;

-- Procedure to borrow a book
DELIMITER //
CREATE PROCEDURE BorrowBook(
    IN p_member_id INT,
    IN p_isbn VARCHAR(13)
)
BEGIN
    DECLARE v_book_available BOOLEAN;
    DECLARE v_member_active BOOLEAN;

    -- Check if book is available
    SELECT Availability = 'In stock' INTO v_book_available
    FROM Books 
    WHERE ISBN = p_isbn;

    -- Check if member is active
    SELECT Status = 'Active' INTO v_member_active
    FROM Members
    WHERE Member_ID = p_member_id;

    IF NOT v_book_available THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Book is not available for borrowing';
    END IF;

    IF NOT v_member_active THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Member account is not active';
    END IF;

    START TRANSACTION;

    -- Update book status
    UPDATE Books 
    SET Availability = 'Checked out'
    WHERE ISBN = p_isbn;

    -- Create transaction record
    INSERT INTO MemberTransactions (Member_ID, ISBN, Transaction_Type, Due_Date, Status)
    VALUES (p_member_id, p_isbn, 'Borrow', DATE_ADD(CURRENT_DATE, INTERVAL 14 DAY), 'Active');

    COMMIT;
END //
DELIMITER ;

-- Procedure to return a book
DELIMITER //
CREATE PROCEDURE ReturnBook(
    IN p_member_id INT,
    IN p_isbn VARCHAR(13)
)
BEGIN
    DECLARE v_transaction_id INT;
    DECLARE v_due_date DATE;
    DECLARE v_fine_amount DECIMAL(10, 2);

    -- Get active transaction
    SELECT Transaction_ID, Due_Date INTO v_transaction_id, v_due_date
    FROM MemberTransactions
    WHERE Member_ID = p_member_id 
    AND ISBN = p_isbn 
    AND Status = 'Active'
    LIMIT 1;

    IF v_transaction_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No active borrowing found for this book';
    END IF;

    -- Calculate fine if overdue (₹10 per day)
    IF CURRENT_DATE > v_due_date THEN
        SET v_fine_amount = DATEDIFF(CURRENT_DATE, v_due_date) * 10;
    ELSE
        SET v_fine_amount = 0;
    END IF;

    START TRANSACTION;

    -- Update book status
    UPDATE Books 
    SET Availability = 'In stock'
    WHERE ISBN = p_isbn;

    -- Update transaction record
    UPDATE MemberTransactions
    SET Return_Date = CURRENT_DATE,
        Fine_Amount = v_fine_amount,
        Status = 'Completed'
    WHERE Transaction_ID = v_transaction_id;

    COMMIT;
END //
DELIMITER ;


CREATE OR REPLACE VIEW BookListView AS
SELECT 
    b.ISBN,
    b.Title,
    a.Author_Name,
    c.Category_Name,
    b.Availability,
    b.Created_At,
    b.Updated_At
FROM Books b
JOIN Authors a ON b.Author_ID = a.Author_ID
JOIN Categories c ON b.Category_ID = c.Category_ID;


-- Create a view for better transaction management
CREATE OR REPLACE VIEW TransactionDetailsView AS
SELECT 
    mt.Transaction_ID,
    m.Member_ID,
    m.Username as Member_Name,
    b.ISBN,
    b.Title as Book_Title,
    a.Author_Name,
    mt.Transaction_Type,
    mt.Transaction_Date,
    mt.Due_Date,
    mt.Return_Date,
    mt.Fine_Amount,
    mt.Status,
    CASE 
        WHEN mt.Status = 'Active' AND mt.Due_Date < CURDATE() 
        THEN DATEDIFF(CURDATE(), mt.Due_Date) * 10 
        ELSE mt.Fine_Amount 
    END as Current_Fine
FROM MemberTransactions mt
JOIN Members m ON mt.Member_ID = m.Member_ID
JOIN Books b ON mt.ISBN = b.ISBN
JOIN Authors a ON b.Author_ID = a.Author_ID;

INSERT INTO Members (Username, Password, First_Name, Last_Name, Email, Status) VALUES
('sarah_johnson', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'Sarah', 'Johnson', 'sarah.johnson@email.com', 'Active'),
('mike_williams', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'Michael', 'Williams', 'mike.williams@email.com', 'Active'),
('emily_brown', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'Emily', 'Brown', 'emily.brown@email.com', 'Active'),
('david_miller', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'David', 'Miller', 'david.miller@email.com', 'Active'),
('lisa_davis', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'Lisa', 'Davis', 'lisa.davis@email.com', 'Suspended'),
('james_wilson', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'James', 'Wilson', 'james.wilson@email.com', 'Active'),
('amy_taylor', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'Amy', 'Taylor', 'amy.taylor@email.com', 'Active'),
('robert_anderson', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'Robert', 'Anderson', 'robert.anderson@email.com', 'Expired'),
('michelle_thomas', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'Michelle', 'Thomas', 'michelle.thomas@email.com', 'Active'),
('kevin_martin', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'Kevin', 'Martin', 'kevin.martin@email.com', 'Active'),
('jennifer_lee', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'Jennifer', 'Lee', 'jennifer.lee@email.com', 'Active'),
('william_clark', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'William', 'Clark', 'william.clark@email.com', 'Active'),
('patricia_white', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'Patricia', 'White', 'patricia.white@email.com', 'Suspended'),
('steven_harris', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'Steven', 'Harris', 'steven.harris@email.com', 'Active'),
('sandra_king', '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'Sandra', 'King', 'sandra.king@email.com', 'Active');



INSERT INTO Authors (Author_Name) VALUES
('G.H. Hardy'),
('Paul Halmos'),
('Richard Courant'),
('Herbert Robbins'),
('James Stewart'),
('Gilbert Strang'),
('Keith Devlin'),
('John Stillwell'),
('Ian Stewart'),
('Edward Frenkel'),
('Timothy Gowers'),
('Terence Tao');

SET @math_category_id = (SELECT Category_ID FROM Categories WHERE Category_Name = 'Mathematics');

-- Insert mathematics books
INSERT INTO Books (ISBN, Title, Author_ID, Category_ID) VALUES
-- Classical Mathematics Books
('9780521720557', 'A Course of Pure Mathematics', 
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'G.H. Hardy'),
    @math_category_id),
    
('9780735611313', 'What Is Mathematics?: An Elementary Approach to Ideas and Methods',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Richard Courant'),
    @math_category_id),

-- Calculus & Analysis
('9781285740621', 'Calculus: Early Transcendentals',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'James Stewart'),
    @math_category_id),
    
('9780980232714', 'Elementary Calculus: An Infinitesimal Approach',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Keith Devlin'),
    @math_category_id),

-- Linear Algebra
('9780980232745', 'Linear Algebra and Its Applications',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Gilbert Strang'),
    @math_category_id),
    
('9780691156668', 'Linear Algebra Done Right',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Paul Halmos'),
    @math_category_id),

-- Number Theory
('9780486682525', 'Elements of Number Theory',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Ian Stewart'),
    @math_category_id),
    
('9780821841778', 'An Introduction to the Theory of Numbers',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'G.H. Hardy'),
    @math_category_id),

-- Advanced Mathematics
('9780465027224', 'Love and Math: The Heart of Hidden Reality',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Edward Frenkel'),
    @math_category_id),
    
('9780465023820', 'Mathematics: A Very Short Introduction',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Timothy Gowers'),
    @math_category_id),

-- Mathematics History & Philosophy
('9780691145013', 'Mathematics and Its History',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'John Stillwell'),
    @math_category_id),
    
('9780691161709', 'Analysis I: Real Analysis',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Terence Tao'),
    @math_category_id);


INSERT INTO Authors (Author_Name) VALUES
('Peter Atkins'),
('Raymond Chang'),
('John McMurry'),
('Paula Bruice'),
('Martin Silberberg');

-- Get the Category_ID for Chemistry
SET @chem_category_id = (SELECT Category_ID FROM Categories WHERE Category_Name = 'Chemistry');

-- Insert chemistry books
INSERT INTO Books (ISBN, Title, Author_ID, Category_ID) VALUES
-- Physical Chemistry
('9780198769866', 'Physical Chemistry: A Molecular Approach', 
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Peter Atkins'),
    @chem_category_id),
    
-- General Chemistry
('9781259911111', 'Chemistry: The Central Science',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Raymond Chang'),
    @chem_category_id),

-- Organic Chemistry
('9780134414232', 'Organic Chemistry: Structure and Function',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'John McMurry'),
    @chem_category_id),
    
-- Advanced Organic Chemistry
('9780321803221', 'Essential Organic Chemistry',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Paula Bruice'),
    @chem_category_id),

-- Inorganic Chemistry
('9780073511184', 'Chemistry: Principles and Practice',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Martin Silberberg'),
    @chem_category_id);


INSERT INTO Authors (Author_Name) VALUES
('Abraham Silberschatz'),
('Raghu Ramakrishnan'),
('C.J. Date'),
('Thomas Connolly'),
('Shamkant Navathe');

-- Get the Category_ID for DBMS
SET @dbms_category_id = (SELECT Category_ID FROM Categories WHERE Category_Name = 'DBMS');

-- Insert DBMS books
INSERT INTO Books (ISBN, Title, Author_ID, Category_ID) VALUES
-- Database System Concepts
('9780073523323', 'Database System Concepts', 
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Abraham Silberschatz'),
    @dbms_category_id),
    
('9780072465631', 'Database Management Systems',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Raghu Ramakrishnan'),
    @dbms_category_id),

('9780321197849', 'An Introduction to Database Systems',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'C.J. Date'),
    @dbms_category_id),
    
('9780321523068', 'Database Systems: A Practical Approach to Design, Implementation, and Management',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Thomas Connolly'),
    @dbms_category_id),

('9780133970777', 'Fundamentals of Database Systems',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Shamkant Navathe'),
    @dbms_category_id);
    
INSERT INTO Authors (Author_Name) VALUES
('Martin Fowler'),
('Robert C. Martin'),
('Eric Evans'),
('Steve McConnell'),
('Ian Sommerville');

-- Get the Category_ID for Software Engineering
SET @se_category_id = (SELECT Category_ID FROM Categories WHERE Category_Name = 'Software Engineering');

-- Insert software engineering books
INSERT INTO Books (ISBN, Title, Author_ID, Category_ID) VALUES
-- Refactoring and Clean Code
('9780134757599', 'Refactoring: Improving the Design of Existing Code', 
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Martin Fowler'),
    @se_category_id),
    
-- Clean Code
('9780132350884', 'Clean Code: A Handbook of Agile Software Craftsmanship',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Robert C. Martin'),
    @se_category_id),

-- Domain-Driven Design
('9780321125217', 'Domain-Driven Design: Tackling Complexity in the Heart of Software',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Eric Evans'),
    @se_category_id),
    
-- Code Complete
('9780735619678', 'Code Complete: A Practical Handbook of Software Construction',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Steve McConnell'),
    @se_category_id),

-- Software Engineering
('9780133943030', 'Software Engineering',
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Ian Sommerville'),
    @se_category_id);
    
INSERT INTO Authors (Author_Name) VALUES 
('Albert Einstein'),
('Richard Feynman'),
('Isaac Newton'),
('Brian Greene');

INSERT INTO Books (ISBN, Title, Author_ID, Category_ID, Availability)
VALUES
('9780141011110', 'Relativity: The Special and the General Theory', 
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Albert Einstein'), 
    (SELECT Category_ID FROM Categories WHERE Category_Name = 'Physics'), 
    'In stock'),


('9780465025275', 'The Feynman Lectures on Physics', 
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Richard Feynman'), 
    (SELECT Category_ID FROM Categories WHERE Category_Name = 'Physics'), 
    'In stock'),

('9780486600819', 'Principia: Mathematical Principles of Natural Philosophy', 
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Isaac Newton'), 
    (SELECT Category_ID FROM Categories WHERE Category_Name = 'Physics'), 
    'In stock'),

('9780393338102', 'The Elegant Universe: Superstrings, Hidden Dimensions, and the Quest for the Ultimate Theory', 
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Brian Greene'), 
    (SELECT Category_ID FROM Categories WHERE Category_Name = 'Physics'), 
    'In stock');


DELIMITER //

CREATE PROCEDURE DeleteBook(
    IN p_admin_id INT,
    IN p_isbn VARCHAR(13)
)
BEGIN
    DECLARE v_book_exists INT;
    DECLARE v_active_transactions INT;
    
    -- Check if book exists
    SELECT COUNT(*) INTO v_book_exists
    FROM Books
    WHERE ISBN = p_isbn;
    
    -- Check if book has any active transactions
    SELECT COUNT(*) INTO v_active_transactions
    FROM MemberTransactions
    WHERE ISBN = p_isbn AND Status = 'Active';
    
    -- Only proceed if book exists and has no active transactions
    IF v_book_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Book does not exist';
    ELSEIF v_active_transactions > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot delete book with active transactions';
    ELSE
        -- Delete the book
        DELETE FROM Books WHERE ISBN = p_isbn;
    END IF;
END //

DELIMITER ;

CREATE TABLE MemberBorrowingSummary (
    Member_ID INT PRIMARY KEY,
    Total_Books_Borrowed INT DEFAULT 0,
    Currently_Borrowed INT DEFAULT 0,
    Total_Fines_Paid DECIMAL(10, 2) DEFAULT 0.00,
    Last_Borrowed_Date TIMESTAMP,
    FOREIGN KEY (Member_ID) REFERENCES Members(Member_ID)
);

DELIMITER //
-- Trigger to initialize summary when new member is created
CREATE TRIGGER after_member_insert 
AFTER INSERT ON Members
FOR EACH ROW
BEGIN
    INSERT INTO MemberBorrowingSummary (Member_ID)
    VALUES (NEW.Member_ID);
END;//

DELIMITER //
-- Trigger to update borrowing summary when a book is borrowed
CREATE TRIGGER after_transaction_insert
AFTER INSERT ON MemberTransactions
FOR EACH ROW
BEGIN
    IF NEW.Transaction_Type = 'Borrow' THEN
        UPDATE MemberBorrowingSummary
        SET Total_Books_Borrowed = Total_Books_Borrowed + 1,
            Currently_Borrowed = Currently_Borrowed + 1,
            Last_Borrowed_Date = NEW.Transaction_Date
        WHERE Member_ID = NEW.Member_ID;
    END IF;
END;//

DELIMITER //
CREATE TRIGGER after_transaction_update
AFTER UPDATE ON MemberTransactions
FOR EACH ROW
BEGIN
    IF NEW.Status = 'Completed' AND OLD.Status = 'Active' THEN
        UPDATE MemberBorrowingSummary
        SET Currently_Borrowed = Currently_Borrowed - 1,
            Total_Fines_Paid = Total_Fines_Paid + NEW.Fine_Amount
        WHERE Member_ID = NEW.Member_ID;
    END IF;
END;//

DELIMITER //
CREATE TRIGGER before_borrow_check
BEFORE INSERT ON MemberTransactions
FOR EACH ROW
BEGIN
    DECLARE overdue_count INT;
    
    SELECT COUNT(*) INTO overdue_count
    FROM MemberTransactions
    WHERE Member_ID = NEW.Member_ID
    AND Status = 'Active'
    AND Due_Date < CURDATE();
    
    IF overdue_count > 0 AND NEW.Transaction_Type = 'Borrow' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot borrow new books while having overdue books';
    END IF;
END;//

DELIMITER //
CREATE TABLE BookStatusLog (
    Log_ID INT PRIMARY KEY AUTO_INCREMENT,
    ISBN VARCHAR(13),
    Old_Status VARCHAR(20),
    New_Status VARCHAR(20),
    Changed_At TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    Changed_By VARCHAR(100),
    FOREIGN KEY (ISBN) REFERENCES Books(ISBN)
);//

DELIMITER //
CREATE TRIGGER after_book_status_change
AFTER UPDATE ON Books
FOR EACH ROW
BEGIN
    IF NEW.Availability != OLD.Availability THEN
        INSERT INTO BookStatusLog (ISBN, Old_Status, New_Status, Changed_By)
        VALUES (NEW.ISBN, OLD.Availability, NEW.Availability, CURRENT_USER());
    END IF;
END;//

SET @mechanics_category_id = (SELECT Category_ID FROM Categories WHERE Category_Name = 'Mechanics and Mechanical');
INSERT INTO Authors (Author_Name) VALUES
('David Dowling'),
('Benson Tongue'),
('Deborah Kaminski'),
('Gordon Kirk'),
('Ali Sadegh');

INSERT INTO Books (ISBN, Title, Author_ID, Category_ID, Availability) VALUES
('9780133514223', 'An Introduction to Mechanical Engineering', 
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'David Dowling'), 
    (SELECT Category_ID FROM Categories WHERE Category_Name = 'Mechanics and Mechanical'), 
    'In stock'),

('9780470554418', 'Principles of Vibration', 
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Benson Tongue'), 
    (SELECT Category_ID FROM Categories WHERE Category_Name = 'Mechanics and Mechanical'), 
    'In stock'),

('9780134593809', 'Introduction to Thermal Systems Engineering', 
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Deborah Kaminski'), 
    (SELECT Category_ID FROM Categories WHERE Category_Name = 'Mechanics and Mechanical'), 
    'In stock'),

('9780133514360', 'Basic Engineering Circuit Analysis', 
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Gordon Kirk'), 
    (SELECT Category_ID FROM Categories WHERE Category_Name = 'Mechanics and Mechanical'), 
    'In stock'),

('9780131412286', 'Fundamentals of Fluid Mechanics', 
    (SELECT Author_ID FROM Authors WHERE Author_Name = 'Ali Sadegh'), 
    (SELECT Category_ID FROM Categories WHERE Category_Name = 'Mechanics and Mechanical'), 
    'In stock');
    
-- Function to calculate total fines for a member
DELIMITER //
CREATE FUNCTION CalculateTotalFines(p_member_id INT) 
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
    DECLARE total_fines DECIMAL(10,2);
    
    SELECT SUM(Fine_Amount)
    INTO total_fines
    FROM MemberTransactions
    WHERE Member_ID = p_member_id;
    
    RETURN COALESCE(total_fines, 0.00);
END //
DELIMITER ;


-- Function to get book availability status with additional details
DELIMITER //
CREATE FUNCTION GetBookAvailabilityDetails(p_isbn VARCHAR(13)) 
RETURNS VARCHAR(100)
DETERMINISTIC
BEGIN
    DECLARE status VARCHAR(100);
    DECLARE due_date DATE;
    
    SELECT 
        CASE 
            WHEN b.Availability = 'In stock' THEN 'Available'
            ELSE CONCAT('Checked out until ', DATE_FORMAT(mt.Due_Date, '%Y-%m-%d'))
        END INTO status
    FROM Books b
    LEFT JOIN MemberTransactions mt ON b.ISBN = mt.ISBN 
        AND mt.Status = 'Active'
    WHERE b.ISBN = p_isbn
    LIMIT 1;
    
    RETURN COALESCE(status, 'Book not found');
END //
DELIMITER ;

-- Nested Query: Find books that have never been borrowed
SELECT b.ISBN, 
       b.Title, 
       a.Author_Name,
       c.Category_Name
FROM Books b
JOIN Authors a ON b.Author_ID = a.Author_ID
JOIN Categories c ON b.Category_ID = c.Category_ID
WHERE b.ISBN NOT IN (
    SELECT DISTINCT ISBN 
    FROM MemberTransactions
);

-- Aggregate Query: Calculate borrowing statistics by category
SELECT 
    c.Category_Name,
    COUNT(DISTINCT mt.ISBN) as total_books_borrowed,
    COUNT(DISTINCT mt.Member_ID) as unique_borrowers,
    AVG(mt.Fine_Amount) as average_fine,
    SUM(CASE WHEN mt.Status = 'Overdue' THEN 1 ELSE 0 END) as overdue_count
FROM Categories c
JOIN Books b ON c.Category_ID = b.Category_ID
LEFT JOIN MemberTransactions mt ON b.ISBN = mt.ISBN
GROUP BY c.Category_Name
ORDER BY total_books_borrowed DESC;

-- Complex Nested Query: Find members with overdue books and their fine details
SELECT 
    m.Member_ID,
    m.First_Name,
    m.Last_Name,
    m.Email,
    COUNT(mt.Transaction_ID) as overdue_books,
    SUM(
        CASE 
            WHEN mt.Status = 'Active' AND mt.Due_Date < CURDATE() 
            THEN DATEDIFF(CURDATE(), mt.Due_Date) * 10 
            ELSE mt.Fine_Amount 
        END
    ) as total_fines
FROM Members m
JOIN MemberTransactions mt ON m.Member_ID = mt.Member_ID
WHERE mt.Status = 'Active' 
AND mt.Due_Date < CURDATE()
GROUP BY m.Member_ID, m.First_Name, m.Last_Name, m.Email
HAVING total_fines > (
    SELECT AVG(Fine_Amount) 
    FROM MemberTransactions 
    WHERE Fine_Amount > 0
);


