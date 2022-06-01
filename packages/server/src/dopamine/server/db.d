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
    this(string connString, uint size) @safe
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
                db.socketEvent().wait(connectionTimeout);
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

    T connect(T)(T delegate(scope DbConn conn) @safe dg) @safe
    {
        auto lock = pool.lockConnection;
        // ensure to pass the object rather than the lock to the dg
        scope conn = cast(DbConn) lock;

        try
            return dg(conn);
        catch (ConnectionException ex)
        {
            conn.resetAsync();
            throw ex;
        }
    }
}

final class DbConn : PgConn
{
    private int lastSock = -1;
    private FileDescriptorEvent sockEvent;

    this(string connString) @safe
    {
        super(connString, Yes.async);
    }

    override void finish() @safe
    {
        super.finish();
        destroy(sockEvent);
    }

    void resetAsync() @safe
    {
        resetStart();

        loop: while (true)
        {
            final switch (connectPoll)
            {
            case PostgresPollingStatus.READING:
                socketEvent().wait(connectionTimeout);
                continue loop;
            case PostgresPollingStatus.WRITING:
                // no implementation of waiting for write
                vibeSleep(dur!"msecs"(10));
                continue loop;
            case PostgresPollingStatus.OK:
                break loop;
            case PostgresPollingStatus.FAILED:
                throw new ConnectionException(errorMessage);
            }
        }
    }

    override protected void pollResult() @safe
    {
        while (!isBusy)
        {
            if (status == ConnStatus.BAD)
                throw new ConnectionException(errorMessage);

            socketEvent().wait(queryTimout);
            consumeInput();
        }
    }

    // current impl of FileDescriptorEvent has the flaw
    // that it closes the file descriptor during descruction.
    // So we need to duplicate the socket descriptor.
    // To avoid having to do this on every query we cache the FileDescriptorEvent
    // and rebuild it each time the postgres socket changes
    // (it is not guaranteed to remain the same, but hopefully doesn't change too often)
    private FileDescriptorEvent socketEvent() @safe
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
            else version (Windows)
            {
                // declaration of _dup hereunder
                const sockDup = _dup(sock);
            }
            else
            {
                static assert(false, "unsupported platform");
            }
            enforce(sockDup != -1, "could not duplicate PostgreSQL socket");
            sockEvent = createFileDescriptorEvent(sockDup, FileDescriptorEvent.Trigger.read);
        }
        return sockEvent;
    }
}

// _dup is part of UCRT, available on Windows 10 onwards.
// No such binding in druntime however
version (Windows) extern (Windows) nothrow @nogc @system int _dup(int);
