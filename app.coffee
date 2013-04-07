## Static
port = 3001
version = "0.1"


## Express
express = require 'express'
app = express()


## Socket.io
server = require('http').createServer(app)
io = require('socket.io').listen(server)


## Redis
redis = require('redis').createClient()
redis_db = 1
redis.select redis_db


## Express Configuration
app.use express.bodyParser()
app.configure () ->
  app.set 'views', __dirname + '/views'
  app.set 'view engine', 'jade'
  app.set 'view options', pretty: true
  app.use express.cookieParser()
  app.use express.bodyParser()
  app.use express.methodOverride()
  app.use app.router
  app.use express.static(__dirname + '/public')

app.configure 'development', () ->
  app.locals.pretty = true
  app.use(express.errorHandler({ dumpExceptions: true, showStack: true }))

app.configure 'production', () ->
  app.use(express.errorHandler())


## Helper functions
error = (s) ->
  response = {response: {status: "ERROR", msg: s}}
  JSON.stringify response
  response

ok = (o) ->
  o.status = "OK"
  response = {response: o}
  response

redis.on "error", (err) ->
  console.log "Redis error:", err


## Routes
app.get '/', (req, res, next) ->
  res.redirect '/home'

app.get '/status', (req, res, next) ->
  res.send 'Chatter server listening on port ' + port

app.post '/login', (req, res, next) ->
  username = req.body.username
  res.cookie 'username', username
  res.redirect '/home'

app.get /^\/login(.*)/, (req, res, next) ->
  res.clearCookie 'username'
  data = page: 'login', username: ''
  res.render 'index', data

app.get '/logout', (req, res, next) ->
  res.clearCookie 'username'
  res.redirect '/login'

get_topics_by_user = (username, cb) ->
  redis.lrange 'user:topics:' + username, 0, -1, (err, reply) ->
    if not reply.length
      cb []
    else
      result = []
      for id in reply
        remaining = reply.length
        redis.hgetall 'topic:' + id,  (err, reply) ->
          result.push reply
          remaining -= 1
          if remaining == 0
            cb result

get_questions_by_user = (username, cb) ->
  redis.lrange 'user:questions:' + username, 0, -1, (err, reply) ->
    if not reply.length
      cb []
    else
      result = []
      remaining = reply.length
      for id in reply
        redis.hgetall 'question:' + id, (err, reply) ->
          result.push reply
          remaining -= 1
          if remaining == 0
            cb result

app.get '/home', (req, res, next) ->
  username = req.cookies.username
  if typeof(username) == 'undefined'
    res.redirect '/login?error=login_required'
  else
    get_topics_by_user username, (topics) ->
      get_questions_by_user username, (questions) ->
          data =
            page: 'home'
            user_topics: topics
            user_questions: questions
            username: username
          res.render 'index', data

app.post '/topic/create', (req, res, next) ->
  username = req.cookies.username
  name = req.body.name
  if typeof(username) == 'undefined'
    res.redirect '/login?error=login_required'
  else
    redis.sadd 'global:topicNames', name, (err, reply) ->
      if reply == 0
        # TODO - handle this better.  This error handler is not the one to use.
        res.send error('topic name already in use.  try again')
      else
        redis.incr 'global:nextTopicId', (err, reply) ->
          topic_id = reply
          redis.hset 'topicIdsByName', name, topic_id, (err, reply) ->
            data =
              id: topic_id.toString(),
              name: name,
              creator: username,
              created: (new Date()).getTime().toString()
            redis.hmset 'topic:' + topic_id, data, (err, reply) ->
              redis.lpush 'user:topics:' + username, topic_id, (err, reply) ->
                res.redirect '/topic/moderate/' + topic_id

app.get '/topic/moderate/:topic_id', (req, res, next) ->
  username = req.cookies.username
  topic_id = req.params.topic_id
  if typeof(username) == 'undefined'
    res.redirect '/login?error=login_required'
  else
    redis.hget 'topic:' + topic_id, 'creator', (err, reply) ->
      if reply != username
        res.redirect '/login?error=access_denied._user_is_not_moderator'
      else
        redis.hget 'topic:' + topic_id, 'name', (e, reply) ->
          data =
            username: username
            page: 'moderate'
            topic:
              name: reply
              id: topic_id
          res.render 'index', data

app.get '/topic/watch/:topic_id', (req, res, next) ->
  username = req.cookies.username
  if typeof(username) == 'undefined'
    res.redirect '/login?error=login_required'
  else
    topic_id = req.params.topic_id
    redis.hgetall 'topic:' + topic_id, (err, reply) ->
      data =
        username: username
        page: 'watch'
        topic: reply
      res.render 'index', data

app.post '/topic/watch', (req, res, next) ->
  name = req.body.name
  redis.hget 'topicIdsByName', name, (err, reply) ->
    if not reply
      res.redirect '/home?error=no_topic_found_with_name'
    else
      res.redirect '/topic/watch/' + reply

## AJAX Handlers
app.post '/submit-question', (req, res, next) ->
  username = req.cookies.username
  topic_id = req.body.topic_id
  question = req.body.question

  if typeof(username) == 'undefined'
    res.send error('username not set')
  else
    redis.incr 'global:nextQuestionId', (err, reply) ->
      question_id = reply.toString()
      data =
        id: question_id,
        text: question,
        topic_id: topic_id,
        creator: username,
        created: (new Date()).getTime().toString()
      redis.hmset 'question:' + reply, data, (err, reply) ->
        redis.lpush 'topic:questions:' + topic_id, question_id, (err, reply) ->
            redis.lpush 'user:questions:' + topic_id, question_id, (err, reply) ->
              # Publish
              io.sockets.in('moderate_' + topic_id).emit('questions', questions: [data])
              # Send Response
              res.send ok("Question submitted successfully.")

## Websockets
io.sockets.on 'connection', (socket) ->

  socket.on 'moderate_topic', (data) ->
    socket.join 'moderate_' + data.topic_id

  socket.on 'event_start_user_typing', (data) ->
    io.sockets.in('moderate_' + data.topic_id).emit('event_start_user_typing', {username: data.username})

  socket.on 'event_end_user_typing', (data) ->
    io.sockets.in('moderate_' + data.topic_id).emit('event_end_user_typing', {username: data.username})

  socket.on 'get_questions', (data) ->
    topic_id = data.topic_id
    questions = []
    redis.lrange 'topic:questions:' + topic_id, 0, -1, (err, reply) ->
      question_ids = reply
      if not question_ids.length
        socket.emit 'questions', questions: questions
      else
        remaining = question_ids.length
        for question_id in question_ids
          redis.hgetall 'question:' + question_id, (err, reply) ->
            questions.push reply
            remaining -= 1
            if remaining == 0
              console.log 'sending at location 2'
              socket.emit 'questions', questions: questions


## Start the app
server.listen port
console.log 'Chatter server listening on port %d', port
