import mysql.connector
from datetime import datetime

def connect_to_database():
    try:
        connection = mysql.connector.connect(
            host="localhost",
            user="root",
            password="12345",
            database="lib_mgmt"
        )
        return connection
    except mysql.connector.Error as error:
        print(f"Error connecting to database: {error}")
        return None

def add_book():
    print("\n=== Add New Book ===")
    isbn = input("Enter ISBN: ")
    title = input("Enter Title: ")
    author = input("Enter Author: ")
    category = input("Enter Category: ")
    
    conn = connect_to_database()
    if not conn:
        return
    
    try:
        cursor = conn.cursor()
        
        # Check if author exists
        cursor.execute("SELECT Author_ID FROM Authors WHERE Author_Name = %s", (author,))
        author_result = cursor.fetchone()
        
        if author_result:
            author_id = author_result[0]
        else:
            cursor.execute("INSERT INTO Authors (Author_Name) VALUES (%s)", (author,))
            author_id = cursor.lastrowid
        
        # Get category ID
        cursor.execute("SELECT Category_ID FROM Categories WHERE Category_Name = %s", (category,))
        category_result = cursor.fetchone()
        
        if not category_result:
            print("Invalid category!")
            return
        
        category_id = category_result[0]
        
        # Insert book
        cursor.execute("""
            INSERT INTO Books (ISBN, Title, Author_ID, Category_ID) 
            VALUES (%s, %s, %s, %s)
        """, (isbn, title, author_id, category_id))
        
        conn.commit()
        print("Book added successfully!")
    except mysql.connector.Error as error:
        print(f"Error adding book: {error}")
    finally:
        conn.close()

def add_member():
    print("\n=== Add New Member ===")
    username = input("Enter Username: ")
    password = input("Enter Password: ")
    first_name = input("Enter First Name: ")
    last_name = input("Enter Last Name: ")
    email = input("Enter Email: ")
    
    conn = connect_to_database()
    if not conn:
        return
    
    try:
        cursor = conn.cursor()
        
        # Check if username exists
        cursor.execute("SELECT COUNT(*) FROM Members WHERE Username = %s", (username,))
        if cursor.fetchone()[0] > 0:
            print("Username already exists!")
            return
        
        # Insert member
        cursor.execute("""
            INSERT INTO Members 
            (Username, Password, First_Name, Last_Name, Email, Status) 
            VALUES (%s, %s, %s, %s, %s, 'Active')
        """, (username, password, first_name, last_name, email))
        
        conn.commit()
        print("Member added successfully!")
    except mysql.connector.Error as error:
        print(f"Error adding member: {error}")
    finally:
        conn.close()

def view_books():
    print("\n=== View Books ===")
    conn = connect_to_database()
    if not conn:
        return
    
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT 
                b.ISBN,
                b.Title,
                a.Author_Name,
                c.Category_Name,
                CASE 
                    WHEN EXISTS (
                        SELECT 1 FROM MemberTransactions mt 
                        WHERE mt.ISBN = b.ISBN AND mt.Status = 'Active'
                    ) THEN 'Borrowed'
                    ELSE 'Available'
                END as Status
            FROM Books b
            JOIN Authors a ON b.Author_ID = a.Author_ID
            JOIN Categories c ON b.Category_ID = c.Category_ID
        """)
        
        books = cursor.fetchall()
        if not books:
            print("No books found!")
            return
            
        print("\nBook List:")
        print("-" * 80)
        print(f"{'ISBN':<15} {'Title':<25} {'Author':<20} {'Category':<15} {'Status':<10}")
        print("-" * 80)
        
        for book in books:
            print(f"{book['ISBN']:<15} {book['Title'][:24]:<25} {book['Author_Name'][:19]:<20} "
                  f"{book['Category_Name'][:14]:<15} {book['Status']:<10}")
    except mysql.connector.Error as error:
        print(f"Error viewing books: {error}")
    finally:
        conn.close()

def delete_book():
    print("\n=== Delete Book ===")
    isbn = input("Enter ISBN of book to delete: ")
    
    conn = connect_to_database()
    if not conn:
        return
    
    try:
        cursor = conn.cursor()
        
        # Check if book exists and is not borrowed
        cursor.execute("""
            SELECT b.Title, 
                   EXISTS (
                       SELECT 1 FROM MemberTransactions mt 
                       WHERE mt.ISBN = b.ISBN AND mt.Status = 'Active'
                   ) as is_borrowed
            FROM Books b
            WHERE b.ISBN = %s
        """, (isbn,))
        
        result = cursor.fetchone()
        if not result:
            print("Book not found!")
            return
            
        if result[1]:  # is_borrowed
            print("Cannot delete book - currently borrowed!")
            return
            
        # Delete book
        cursor.execute("DELETE FROM Books WHERE ISBN = %s", (isbn,))
        conn.commit()
        print(f"Book '{result[0]}' deleted successfully!")
    except mysql.connector.Error as error:
        print(f"Error deleting book: {error}")
    finally:
        conn.close()

def view_members():
    print("\n=== View Members ===")
    conn = connect_to_database()
    if not conn:
        return
    
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT 
                Member_ID,
                Username,
                First_Name,
                Last_Name,
                Email,
                Status,
                (SELECT COUNT(*) FROM MemberTransactions 
                 WHERE Member_ID = m.Member_ID AND Status = 'Active') as Active_Borrows
            FROM Members m
            ORDER BY Member_ID
        """)
        
        members = cursor.fetchall()
        if not members:
            print("No members found!")
            return
            
        print("\nMember List:")
        print("-" * 100)
        print(f"{'ID':<5} {'Username':<15} {'Name':<25} {'Email':<25} {'Status':<10} {'Active Borrows':<15}")
        print("-" * 100)
        
        for member in members:
            full_name = f"{member['First_Name']} {member['Last_Name']}"
            print(f"{member['Member_ID']:<5} {member['Username']:<15} {full_name[:24]:<25} "
                  f"{member['Email'][:24]:<25} {member['Status']:<10} {member['Active_Borrows']:<15}")
    except mysql.connector.Error as error:
        print(f"Error viewing members: {error}")
    finally:
        conn.close()

def delete_member():
    print("\n=== Delete Member ===")
    
    # First show the list of members
    view_members()
    
    member_id = input("\nEnter Member ID to delete: ")
    
    conn = connect_to_database()
    if not conn:
        return
    
    try:
        cursor = conn.cursor()
        
        # Check if member exists and has no active borrows
        cursor.execute("""
            SELECT 
                CONCAT(First_Name, ' ', Last_Name) as full_name,
                (SELECT COUNT(*) FROM MemberTransactions 
                 WHERE Member_ID = m.Member_ID AND Status = 'Active') as active_borrows
            FROM Members m
            WHERE Member_ID = %s
        """, (member_id,))
        
        result = cursor.fetchone()
        if not result:
            print("Member not found!")
            return
            
        if result[1] > 0:  # active_borrows
            print(f"Cannot delete member - has {result[1]} active borrows!")
            return
            
        # Delete member
        cursor.execute("DELETE FROM Members WHERE Member_ID = %s", (member_id,))
        conn.commit()
        print(f"Member '{result[0]}' deleted successfully!")
    except mysql.connector.Error as error:
        print(f"Error deleting member: {error}")
    finally:
        conn.close()

def main():
    while True:
        print("\n=== Exam Centre Management System ===")
        print("1. Add Book")
        print("2. Add Member")
        print("3. View Books")
        print("4. View Members")
        print("5. Delete Book")
        print("6. Delete Member")
        print("7. Exit")
        
        choice = input("\nEnter your choice (1-7): ")
        
        if choice == '1':
            add_book()
        elif choice == '2':
            add_member()
        elif choice == '3':
            view_books()
        elif choice == '4':
            view_members()
        elif choice == '5':
            delete_book()
        elif choice == '6':
            delete_member()
        elif choice == '7':
            print("\nThank you for using the Exam Centre  Management System!")
            break
        else:
            print("\nInvalid choice! Please try again.")

if __name__ == "__main__":
    main()