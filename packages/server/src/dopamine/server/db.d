module dopamine.server.db;

import pgd.conn;

import vibe.core.connectionpool;
import vibe.core.core;

import std.exception;
import std.typecons;
import core.time;

private alias vibeSleep = vibe.core.core.sleep;

private enum connectionTimeout = dur!"seconds"(10);
private enum queryTimout = dur!"seconds"(30);

final class DbClient
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

        loop: while (true)
        {
            final switch (db.connectPoll)
            {
            case PostgresPollingStatus.READING:
                db.socketEvent.wait(connectionTimeout);
                continue loop;
            case PostgresPollingStatus.WRITING:
                // no implementation of waiting for write
                vibeSleep(dur!"msecs"(10));
                continue loop;
            case PostgresPollingStatus.OK:
                break loop;
            case PostgresPollingStatus.FAILED:
                throw new ConnectionException(db.errorMessage);
            }
        }

        assert(db.status == ConnStatus.OK);

        return db;
    }

    void connect(alias fun)()
    {
        auto lock = pool.lockConnection;
        // ensure to pass the object rather than the lock to the dg
        auto conn = cast(DbConn) lock;

        try
            return fun(conn);
        catch (ConnectionException ex)
            conn.resetAsync();
    }
}

final class DbConn : PgConn
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

    void resetAsync()
    {
        resetStart();

        loop: while (true)
        {
            final switch (db.connectPoll)
            {
            case PostgresPollingStatus.READING:
                socketEvent.wait(connectionTimeout);
                continue loop;
            case PostgresPollingStatus.WRITING:
                // no implementation of waiting for write
                vibeSleep(dur!"msecs"(10));
                continue loop;
            case PostgresPollingStatus.OK:
                break loop;
            case PostgresPollingStatus.FAILED:
                throw new ConnectionException(db.errorMessage);
            }
        }
    }

    override protected void pollResult()
    {
        while (!isBusy)
        {
            if (status == ConnStatus.BAD)
                throw new ConnectionException(errorMessage);

            socketEvent.wait(queryTimout);
            consumeInput();
        }
    }

    // current impl of FileDescriptorEvent has the flaw
    // that it closes the file descriptor during descruction.
    // So we need to duplicate the socket descriptor.
    // To avoid having to do this on every query we cache the FileDescriptorEvent
    // and rebuild it each time the postgres socket changes
    // (it is not guaranteed to remain the same, but hopefully doesn't change too often)
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
