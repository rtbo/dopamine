module dopamine.server.db;

import pgd.conn;

import vibe.core.connectionpool;

alias DbConn = PgConn;

class DbClient
{
    ConnectionPool!DbConn pool;

    /// Create a connection pool with specfied size, each connection specified by connString
    this(string conninfo, uint size)
    {
        pool = new ConnectionPool!DbConn(() @safe => new DbConn(conninfo), size);
    }

    LockedConnection!DbConn lockConnection()
    {
        return pool.lockConnection();
    }
}
