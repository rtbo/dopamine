module dopamine.server.db;

import pgd.conn;

import vibe.core.connectionpool;
import vibe.core.core;

import std.exception;
import std.typecons;
import core.time;

private alias vibeSleep = vibe.core.core.sleep;

private enum connectionTimeout = dur!"seconds"(10);
private enum queryTimeout = dur!"seconds"(30);

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
                version (Posix)
                    db.socketEvent()
                        .wait(connectionTimeout);
                else version (Windows) // wait not implemented on Windows
                    vibeSleep(dur!"msecs"(50));
                else
                    static assert(false, "unsupported platform");
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

    T transac(T)(T delegate(scope DbConn conn) @safe dg) @safe
    {
        auto lock = pool.lockConnection;
        // ensure to pass the object rather than the lock to the dg
        scope conn = cast(DbConn) lock;

        try
            return conn.transac(() @safe => dg(conn));
        catch (ConnectionException ex)
        {
            conn.resetAsync();
            throw ex;
        }
    }

    void finish() @safe
    {
        pool.removeUnused((DbConn conn) @safe nothrow{ conn.finish(); });
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

    override void finish() @safe nothrow
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
                version (Posix)
                    socketEvent().wait(connectionTimeout);
                else version (Windows) // wait not implemented on Windows
                    vibeSleep(dur!"msecs"(50));
                else
                    static assert(false, "unsupported platform");
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

            version (Posix)
                socketEvent().wait(queryTimeout);
            else version (Windows) // wait not implemented on Windows
                vibeSleep(dur!"msecs"(50));
            else
                static assert(false, "unsupported platform");

            consumeInput();
        }
    }

    private FileDescriptorEvent socketEvent() @safe
    {
        const sock = super.socket;

        if (sock != lastSock)
        {
            lastSock = sock;
            sockEvent = createFileDescriptorEvent(sock, FileDescriptorEvent.Trigger.read);
        }
        return sockEvent;
    }
}
