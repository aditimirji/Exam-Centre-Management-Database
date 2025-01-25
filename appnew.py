import streamlit as st
import mysql.connector
from datetime import datetime, timedelta
import hashlib
import re

# Configuration and Constants
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "12345",
    "database": "lib_mgmt"
}

# Utility Functions
def get_database_connection():
    try:
        return mysql.connector.connect(**DB_CONFIG)
    except mysql.connector.Error as error:
        st.error(f"Database Connection Error: {error}")
        return None

def hash_password(password):
    """Hash password using SHA-256"""
    return hashlib.sha256(password.encode()).hexdigest()

def validate_isbn(isbn):
    """Validate ISBN format"""
    return bool(re.match(r'^\d{10}|\d{13}$', isbn))

def validate_email(email):
    """Validate email format"""
    return bool(re.match(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$', email))

# Authentication Functions
def check_admin_login(username, password):
    conn = get_database_connection()
    if not conn:
        return False, None
    
    try:
        cursor = conn.cursor(dictionary=True)
        hashed_password = hash_password(password)
        cursor.execute(
            "SELECT Admin_ID, Username, Role FROM Administrators WHERE Username = %s AND Password = %s",
            (username, hashed_password)
        )
        result = cursor.fetchone()
        if result:
            return True, result
        return False, None
    except mysql.connector.Error as error:
        st.error(f"Login Error: {error}")
        return False, None
    finally:
        conn.close()

def check_member_login(username, password):
    conn = get_database_connection()
    if not conn:
        return False, None
    
    try:
        cursor = conn.cursor(dictionary=True)
        hashed_password = hash_password(password)
        
        print(f"Attempting login with Username: {username} and Hashed Password: {hashed_password}")  # Debug
        
        cursor.execute(
            "SELECT Member_ID, Username, Status FROM Members WHERE Username = %s AND Password = %s",
            (username, hashed_password)
        )
        result = cursor.fetchone()
        
        print(f"Login query result: {result}")  # Debug
        
        if result and result['Status'] == 'Active':
            return True, result
        return False, None
    except mysql.connector.Error as error:
        st.error(f"Login Error: {error}")
        return False, None
    finally:
        conn.close()


# Book Management Functions
def fetch_books(search_term=None):
    conn = get_database_connection()
    if not conn:
        return []
    
    try:
        cursor = conn.cursor(dictionary=True)
        if search_term:
            query = """
                SELECT * FROM BookListView 
                WHERE Title LIKE %s 
                OR Author_Name LIKE %s 
                OR Category_Name LIKE %s
            """
            search_pattern = f"%{search_term}%"
            cursor.execute(query, (search_pattern, search_pattern, search_pattern))
        else:
            cursor.execute("SELECT * FROM BookListView")
        return cursor.fetchall()
    except mysql.connector.Error as error:
        st.error(f"Error fetching books: {error}")
        return []
    finally:
        conn.close()

def add_book(admin_id, isbn, title, author, category):
    if not validate_isbn(isbn):
        st.error("Invalid ISBN format")
        return False
    
    conn = get_database_connection()
    if not conn:
        return False
    
    try:
        cursor = conn.cursor()
        
        # First, check if author exists, if not create
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
            st.error("Invalid category")
            return False
        
        category_id = category_result[0]
        
        # Insert the book
        cursor.execute("""
            INSERT INTO Books (ISBN, Title, Author_ID, Category_ID) 
            VALUES (%s, %s, %s, %s)
        """, (isbn, title, author_id, category_id))
        
        conn.commit()
        st.success("Book added successfully")
        return True
    except mysql.connector.Error as error:
        st.error(f"Error adding book: {error}")
        return False
    finally:
        conn.close()

def delete_book(admin_id, isbn):
    conn = get_database_connection()
    if not conn:
        return False
    
    try:
        cursor = conn.cursor()
        cursor.execute("CALL DeleteBook(%s, %s)", (admin_id, isbn))
        conn.commit()
        st.success("Book deleted successfully")
        return True
    
    except mysql.connector.Error as error:
        st.error(f"Error deleting book: {error}")
        return False
    finally:
        conn.close()

def borrow_book(member_id, isbn):
    conn = get_database_connection()
    if not conn:
        return False
    
    try:
        cursor = conn.cursor()
        
        # Check if member has any overdue books
        cursor.execute("""
            SELECT COUNT(*) 
            FROM MemberTransactions 
            WHERE Member_ID = %s 
            AND Status = 'Active' 
            AND Due_Date < CURDATE()
        """, (member_id,))
        
        overdue_count = cursor.fetchone()[0]
        if overdue_count > 0:
            st.error("Cannot borrow new books while you have overdue items")
            return False
            
        # Check if member already has this book
        cursor.execute("""
            SELECT COUNT(*) 
            FROM MemberTransactions 
            WHERE Member_ID = %s 
            AND ISBN = %s 
            AND Status = 'Active'
        """, (member_id, isbn))
        
        current_borrow = cursor.fetchone()[0]
        if current_borrow > 0:
            st.error("You already have this book borrowed")
            return False
        
        # Call the BorrowBook stored procedure
        cursor.callproc('BorrowBook', (member_id, isbn))
        conn.commit()
        st.success("Book borrowed successfully")
        return True
    except mysql.connector.Error as error:
        st.error(f"Error borrowing book: {error}")
        return False
    finally:
        conn.close()
def return_book(member_id, isbn):
    conn = get_database_connection()
    if not conn:
        return False
    
    try:
        cursor = conn.cursor()
        
        # Call the ReturnBook stored procedure
        cursor.callproc('ReturnBook', (member_id, isbn))
        conn.commit()
        
        # Fetch any fines after return
        cursor.execute("""
            SELECT Fine_Amount 
            FROM MemberTransactions 
            WHERE Member_ID = %s 
            AND ISBN = %s 
            AND Status = 'Completed'
            ORDER BY Return_Date DESC 
            LIMIT 1
        """, (member_id, isbn))
        
        fine_result = cursor.fetchone()
        if fine_result and fine_result[0] > 0:
            st.warning(f"Book returned with a fine of ₹{fine_result[0]}. Please pay at the library counter.")
        else:
            st.success("Book returned successfully")
        return True
    except mysql.connector.Error as error:
        st.error(f"Error returning book: {error}")
        return False
    finally:
        conn.close()
def fetch_member_transactions(member_id):
    conn = get_database_connection()
    if not conn:
        return []
    
    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute("""
            SELECT 
                mt.Transaction_ID,
                b.Title,
                mt.ISBN,
                mt.Transaction_Type,
                mt.Transaction_Date,
                mt.Due_Date,
                mt.Return_Date,
                mt.Fine_Amount,
                mt.Status
            FROM MemberTransactions mt
            JOIN Books b ON mt.ISBN = b.ISBN
            WHERE mt.Member_ID = %s
            ORDER BY mt.Transaction_Date DESC
        """, (member_id,))
        return cursor.fetchall()
    except mysql.connector.Error as error:
        st.error(f"Error fetching transactions: {error}")
        return []
    finally:
        conn.close()

def register_new_member(username, password, first_name, last_name, email):
    if not validate_email(email):
        st.error("Invalid email format")
        return False
        
    conn = get_database_connection()
    if not conn:
        return False
    
    try:
        cursor = conn.cursor()
        
        # Check if username already exists
        cursor.execute("SELECT COUNT(*) FROM Members WHERE Username = %s", (username,))
        if cursor.fetchone()[0] > 0:
            st.error("Username already exists")
            return False
            
        # Check if email already exists
        cursor.execute("SELECT COUNT(*) FROM Members WHERE Email = %s", (email,))
        if cursor.fetchone()[0] > 0:
            st.error("Email already exists")
            return False
        
        # Insert new member
        hashed_password = hash_password(password)
        cursor.execute("""
            INSERT INTO Members 
            (Username, Password, First_Name, Last_Name, Email, Status) 
            VALUES (%s, %s, %s, %s, %s, 'Active')
        """, (username, hashed_password, first_name, last_name, email))
        
        conn.commit()
        st.success("Member registered successfully")
        return True
    except mysql.connector.Error as error:
        st.error(f"Error registering member: {error}")
        return False
    finally:
        conn.close()

def fetch_all_members():
    conn = get_database_connection()
    if not conn:
        return []
    
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
                Created_At,
                Last_Login
            FROM Members
            ORDER BY Created_At DESC
        """)
        return cursor.fetchall()
    except mysql.connector.Error as error:
        st.error(f"Error fetching members: {error}")
        return []
    finally:
        conn.close()
# UI Components
def login_page():
    st.title("Exam Centre Management System")
    
    login_type = st.radio("Select Login Type", ["Member", "Administrator"])
    
    with st.form("login_form"):
        username = st.text_input("Username")
        password = st.text_input("Password", type="password")
        submit = st.form_submit_button("Login")
        
        if submit:
            if login_type == "Administrator":
                success, user_data = check_admin_login(username, password)
                if success:
                    st.session_state['logged_in'] = True
                    st.session_state['user_type'] = 'admin'
                    st.session_state['user_data'] = user_data
                    st.success(f"Welcome, Administrator {username}!")
                    st.rerun()
                else:
                    st.error("Invalid administrator credentials")
            else:
                success, user_data = check_member_login(username, password)
                if success:
                    st.session_state['logged_in'] = True
                    st.session_state['user_type'] = 'member'
                    st.session_state['user_data'] = user_data
                    st.success(f"Welcome, Member {username}!")
                    st.rerun()
                else:
                    st.error("Invalid member credentials")

def admin_portal():
    st.title("Exam Centre Administration Portal")
    st.write(f"Welcome, {st.session_state['user_data']['Username']}")
    
    menu = st.sidebar.selectbox(
        "Menu",
        ["Add Book", "Delete Book", "View Books", "Register Member", "View Members", "View Member Transactions"]
    )
    
    if st.sidebar.button("Logout"):
        for key in st.session_state.keys():
            del st.session_state[key]
        st.rerun()
    
    if menu == "Add Book":
        st.header("Add New Book")
        with st.form("add_book_form"):
            isbn = st.text_input("ISBN")
            title = st.text_input("Title")
            author = st.text_input("Author")
            category = st.selectbox("Category", 
                                  ["Fiction", "Non-Fiction", "Science", "Technology",
                                   'Chemistry', 'Physics', 'Mechanics and Mechanical',
                                   'DBMS', 'Programming', 'Software Engineering',
                                   'Mathematics', "Other"])
            if st.form_submit_button("Add Book"):
                add_book(st.session_state['user_data']['Admin_ID'], isbn, title, author, category)
    
    elif menu == "Delete Book":
        st.header("Delete Book")
        books = fetch_books()
        if books:
            book_to_delete = st.selectbox(
                "Select book to delete",
                options=books,
                format_func=lambda x: f"{x['Title']} ({x['ISBN']})"
            )
            if st.button("Delete Selected Book"):
                delete_book(st.session_state['user_data']['Admin_ID'], 
                          book_to_delete['ISBN'])
        else:
            st.info("No books available")
    
    elif menu == "View Books":
        st.header("Book Inventory")
        search = st.text_input("Search books by title or author")
        books = fetch_books(search)
        if books:
            st.dataframe(books)
        else:
            st.info("No books found")
            
    elif menu == "Register Member":
        st.header("Register New Member")
        with st.form("register_member_form"):
            col1, col2 = st.columns(2)
            with col1:
                first_name = st.text_input("First Name")
                username = st.text_input("Username")
                email = st.text_input("Email")
            with col2:
                last_name = st.text_input("Last Name")
                password = st.text_input("Password", type="password")
                password_confirm = st.text_input("Confirm Password", type="password")
            
            if st.form_submit_button("Register Member"):
                if not all([username, password, first_name, last_name, email]):
                    st.error("All fields are required")
                elif password != password_confirm:
                    st.error("Passwords do not match")
                else:
                    register_new_member(username, password, first_name, last_name, email)
                    
    elif menu == "View Members":
        st.header("Member List")
        members = fetch_all_members()
        if members:
            # Convert the data to a format suitable for display
            member_data = []
            for member in members:
                member_data.append({
                    "Member ID": member['Member_ID'],
                    "Username": member['Username'],
                    "Name": f"{member['First_Name']} {member['Last_Name']}",
                    "Email": member['Email'],
                    "Status": member['Status'],
                    "Joined": member['Created_At'].strftime("%Y-%m-%d")
                })
            st.dataframe(
                member_data,
                column_config={
                    "Member ID": st.column_config.NumberColumn("Member ID"),
                    "Status": st.column_config.SelectboxColumn(
                        "Status",
                        options=["Active", "Suspended", "Expired"]
                    )
                }
            )
        else:
            st.info("No members found")
            
    elif menu == "View Member Transactions":
        st.header("Member Transactions")
        
        # Fetch all members for the dropdown
        members = fetch_all_members()
        if members:
            selected_member = st.selectbox(
                "Select Member",
                options=members,
                format_func=lambda x: f"{x['First_Name']} {x['Last_Name']} (ID: {x['Member_ID']})"
            )
            
            if selected_member:
                st.subheader(f"Transactions for {selected_member['First_Name']} {selected_member['Last_Name']}")
                transactions = fetch_member_transactions(selected_member['Member_ID'])
                
                if transactions:
                    # Convert dates to string format for better display
                    for transaction in transactions:
                        transaction['Transaction_Date'] = transaction['Transaction_Date'].strftime("%Y-%m-%d")
                        transaction['Due_Date'] = transaction['Due_Date'].strftime("%Y-%m-%d")
                        if transaction['Return_Date']:
                            transaction['Return_Date'] = transaction['Return_Date'].strftime("%Y-%m-%d")
                    
                    # Create a formatted dataframe
                    st.dataframe(
                        transactions,
                        column_config={
                            "Transaction_ID": st.column_config.NumberColumn("Transaction ID"),
                            "Title": "Book Title",
                            "Transaction_Type": "Type",
                            "Transaction_Date": "Issue Date",
                            "Due_Date": "Due Date",
                            "Return_Date": "Return Date",
                            "Fine_Amount": st.column_config.NumberColumn(
                                "Fine Amount",
                                format="₹%d"
                            ),
                            "Status": st.column_config.SelectboxColumn(
                                "Status",
                                options=["Active", "Completed"]
                            )
                        }
                    )
                    
                    # Add some statistics
                    col1, col2, col3 = st.columns(3)
                    with col1:
                        active_books = sum(1 for t in transactions if t['Status'] == 'Active')
                        st.metric("Active Borrows", active_books)
                    with col2:
                        total_fines = sum(t['Fine_Amount'] for t in transactions)
                        st.metric("Total Fines", f"₹{total_fines}")
                    with col3:
                        overdue_books = sum(1 for t in transactions 
                                         if t['Status'] == 'Active' and 
                                         datetime.strptime(t['Due_Date'], "%Y-%m-%d").date() < datetime.now().date())
                        st.metric("Overdue Books", overdue_books)
                else:
                    st.info("No transactions found for this member")
        else:
            st.info("No members found in the system")
            
def member_portal():
    st.title("Exam Centre Member Portal")
    st.write(f"Welcome, {st.session_state['user_data']['Username']}")
    
    menu = st.sidebar.selectbox(
        "Menu",
        ["View Books", "Borrow Book", "Return Book", "My Transactions"]
    )
    
    if st.sidebar.button("Logout"):
        for key in st.session_state.keys():
            del st.session_state[key]
        st.rerun()
    
    if menu == "View Books":
        st.header("Available Books")
        search = st.text_input("Search books by title or author")
        books = fetch_books(search)
        if books:
            st.dataframe(books)
        else:
            st.info("No books found")
    
    elif menu == "Borrow Book":
        st.header("Borrow a Book")
        available_books = [b for b in fetch_books() if b['Availability'] == 'In stock']
        if available_books:
            book_to_borrow = st.selectbox(
                "Select book to borrow",
                options=available_books,
                format_func=lambda x: f"{x['Title']} ({x['ISBN']})"
            )
            if st.button("Borrow Selected Book"):
                borrow_book(st.session_state['user_data']['Member_ID'], 
                          book_to_borrow['ISBN'])
        else:
            st.info("No books available for borrowing")
    
    elif menu == "Return Book":
        st.header("Return a Book")
        transactions = fetch_member_transactions(st.session_state['user_data']['Member_ID'])
        active_transactions = [t for t in transactions if t['Status'] == 'Active']
        
        if active_transactions:
           transaction_to_return = st.selectbox(
                "Select book to return",
                options=active_transactions,
                format_func=lambda x: f"{x['Title']} (Due: {x['Due_Date']})"
            )
           if st.button("Return Selected Book"):
                return_book(st.session_state['user_data']['Member_ID'], 
                          transaction_to_return['ISBN'])
        else:
            st.info("No books to return")
    
    elif menu == "My Transactions":
        st.header("My Transaction History")
        transactions = fetch_member_transactions(st.session_state['user_data']['Member_ID'])
        if transactions:
            st.dataframe(transactions)
        else:
            st.info("No transaction history found")

def main():
    if 'logged_in' not in st.session_state:
        st.session_state['logged_in'] = False
    
    if st.session_state['logged_in']:
        if st.session_state['user_type'] == 'admin':
            admin_portal()
        else:
            member_portal()
    else:
        login_page()

if __name__ == "__main__":
    main()