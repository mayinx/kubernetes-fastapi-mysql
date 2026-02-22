from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from sqlalchemy.engine import create_engine
import os

# creating a FastAPI server
server = FastAPI(title='User API')

# creating a connection to the database
mysql_host = os.getenv("MYSQL_HOST", "127.0.0.1")
mysql_port = os.getenv("MYSQL_PORT", "3306")
mysql_url = f"{mysql_host}:{mysql_port}"

mysql_user = os.getenv("MYSQL_USER", "") # provided via Secret / env only
mysql_password = os.getenv("MYSQL_PASSWORD", "")  # provided via Secret / env only
database_name = os.getenv("MYSQL_DATABASE", "Main")

# recreating the URL connection
connection_url = 'mysql://{user}:{password}@{url}/{database}'.format(
    user=mysql_user,
    password=mysql_password,
    url=mysql_url,
    database=database_name
)

# creating the connection
mysql_engine = create_engine(connection_url)


# creating a User class
class User(BaseModel):
    user_id: int = 0
    username: str = 'daniel'
    email: str = 'daniel@datascientest.com'


@server.get('/status')
async def get_status():
    """Returns 1
    """
    return 1

# NOTE (SQLAlchemy 2.0 change):
# The original lesson code used `connection.execute("SELECT ...")` with a plain SQL string.
# In SQLAlchemy 2.0, plain strings are NOT executable objects anymore, so this raises:
#   sqlalchemy.exc.ObjectNotExecutableError: Not an executable object: 'SELECT ...'
# Fix: use `exec_driver_sql()` for raw SQL strings (minimal change, keeps the rest intact).
@server.get('/users')
async def get_users():
    with mysql_engine.connect() as connection:
        # OLD (lesson code): works in older SQLAlchemy, fails in SQLAlchemy 2.0
        # results = connection.execute('SELECT * FROM Users;')

        # NEW: SQLAlchemy 2.0-compatible way to run a raw SQL string
        results = connection.exec_driver_sql("SELECT * FROM Users;")

    results = [
        User(
            user_id=i[0],
            username=i[1],
            email=i[2]
            ) for i in results.fetchall()]
    return results


# NOTE (FastAPI path parameter syntax):
# The lesson wrote '/users/{user_id:int}', but FastAPI does NOT use that syntax in the path string.
# Correct approach: keep the path as '/users/{user_id}' and type the parameter in the function signature.

# OLD (lesson code): invalid/unsupported path syntax for FastAPI
# @server.get('/users/{user_id:int}', response_model=User)

# NEW: FastAPI-compatible path + typed function argument
@server.get('/users/{user_id}', response_model=User)
async def get_user(user_id: int):
    with mysql_engine.connect() as connection:
        # OLD (lesson code): fails in SQLAlchemy 2.0 (plain string not executable)
        # results = connection.execute(
        #     'SELECT * FROM Users WHERE Users.id = {};'.format(user_id))

        # NEW: SQLAlchemy 2.0-compatible raw SQL execution
        results = connection.exec_driver_sql(
            "SELECT * FROM Users WHERE Users.id = {};".format(user_id)
        )

    results = [
        User(
            user_id=i[0],
            username=i[1],
            email=i[2]
            ) for i in results.fetchall()]

    if len(results) == 0:
        raise HTTPException(
            status_code=404,
            detail='Unknown User ID')
    else:
        return results[0]