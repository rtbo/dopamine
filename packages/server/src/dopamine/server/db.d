module dopamine.server.db;

import dopamine.server.config;
import dopamine.server.pgd;

alias DbConn = dopamine.server.pgd.DbConn;
DbClient client;

shared static this()
{
    const conf = Config.get;

    client = new DbClient(conf.dbConnString, conf.dbPoolMaxSize);
}
