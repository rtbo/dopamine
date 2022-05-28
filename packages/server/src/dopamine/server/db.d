module dopamine.server.db;

import pgd.conn;

import vibe.core.connectionpool;
import vibe.core.core;

import std.exception;
import std.typecons;
import core.time;

private alias vibeSleep = vibe.core.core.sleep;

class DbClient
{
    ConnectionPool!DbConn pool;

    /// Create a connection pool with specfied size, each connection specified by connString
    this(string connString, uint size)
    {
        pool = new ConnectionPool!DbConn(() @safe => createConnection(connString), size);
    }

    private DbConn createConnection(string connString) @trusted
    {
        auto db = new DbConn(connString);

        loop: while(1)
        {
            switch (db.status)
            {
            case ConnStatus.OK:
                break loop;
            case ConnStatus.BAD:
                throw new ConnectionException(db.errorMessage);
            default:
                break;
            }

            switch(db.connectPoll)
            {
            case PostgresPollingStatus.READING:
                db.socketEvent.wait();
                break;
            case PostgresPollingStatus.WRITING:
                //
                vibeSleep(dur!"msecs"(10));
                break;
            default:
                break;
            }
        }

        assert (db.status == ConnStatus.OK);

        return db;
    }


    void connect(alias fun)()
    {
        auto lock = pool.lockConnection;
        // ensure to pass the object rather than the lock to the dg
        auto conn = cast(DbConn) lock;

        try
        {
            fun(conn);
        }
        catch (ConnectionException ex)
        {
            conn.reset();
        }
    }
}

class DbConn : PgConn
{
    private int lastSock = -1;
    private FileDescriptorEvent sockEvent;

    this(string connString)
    {
        super(connString, Yes.async);
    }

    override void finish()
    {
        super.finish();
        destroy(sockEvent);
    }

    private FileDescriptorEvent socketEvent()
    {
        const sock = super.socket;

        if (sock != lastSock)
        {
            lastSock = sock;
            version (Posix)
            {
                import core.sys.posix.unistd : dup;

                const sockDup = dup(sock);
            }
            else
            {
                static assert(false, "socket duplication implementation");
            }
            sockEvent = createFileDescriptorEvent(sockDup, FileDescriptorEvent.Trigger.read);
        }
        return sockEvent;
    }

}
