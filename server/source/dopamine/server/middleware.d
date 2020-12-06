module dopamine.server.middleware;

// import vibe.http.server;

// alias NextHandler = void delegate();

// alias Middleware = void delegate(HTTPServerRequest req, HTTPServerRequest req, NextHandler next);

// class MiddlewareRoute : HTTPServerRequestHandler
// {
//     private Middleware _middlewares;

//     this(Middleware[] middlewares)
//     {
//         _middlewares = middlewares;
//     }

//     void handleRequest(HTTPServerRequest req, HTTPServerResponse res)
//     {
//         if (!_middlewares.length)
//             return;
//         handleMiddleware(req, res, _middlewares[0], 0);
//     }

//     private void handleMiddleware(HTTPServerRequest req, HTTPServerResponse res,
//             Middleware middleware, size_t index)
//     {
//         void next()
//         {
//             index++;
//             if (index >= _middlewares.length)
//                 return;
//             handleMiddleware(_middlewares[index], index);
//         }

//         middleware(req, res, &next);
//     }
// }
