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
log = (s) ->
  console.log s

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
  if username == 'undefined'
    res.redirect '/login?error=requires_login'
  else
    get_topics_by_user username, (topics) ->
      get_questions_by_user username, (questions) ->
          data = 
            page: 'home'
            user_topics: topics
            user_questions: questions
            username: username
          console.log 'data is', data
          res.render 'index', data

app.post '/topic/create', (req, res, next) ->
  username = req.cookies.username
  name = req.body.name
  if username == 'undefined'
    res.redirect '/login?error=requires_login'
  else
    redis.sadd 'global:topicNames', name, (err, reply) ->
      console.log 'here reply is', reply
      if reply == 0
        # TODO - handle this better.  This error handler is not the one to use.
        res.send error('topic name already in use.  try again')
      else
        redis.incr 'global:nextTopicId', (err, reply) ->
          topic_id = reply
          data = id: topic_id.toString(), name: name, creator: username, created: (new Date()).getTime().toString()
          console.log 'data is', data
          redis.hmset 'topic:' + topic_id, data, (err, reply) ->
            console.log 'err is', err
            console.log 'reply is', err
            redis.lpush 'user:topics:' + username, topic_id, (err, reply) ->
              res.redirect '/topic/moderate/' + topic_id

app.get '/topic/moderate/:topic_id', (req, res, next) ->
  username = req.cookies.username
  topic_id = req.params.topic_id
  if username == 'undefined'
    res.redirect '/login?error=requires_login'
  else
    redis.hget 'topic:' + topic_id, 'creator', (err, reply) ->
      #console.log ("reply is", reply)
      if reply != username
        res.redirect '/login?error=user_not_moderator'
      else
        redis.hget 'topic:' + topic_id, 'name', (e, reply) ->
          data = 
            username: username
            page: 'moderate'
            topic: 
              name: reply
              id: topic_id
          res.render 'index', data

app.get '/topic/join/:topic_id', (req, res, next) ->
  topic_id = req.params.topic_id
  redis.hmget 'topic:' + topid_id, ['name', 'creator'], (err, reply) ->
    data = 
      page: 'join'
      topic: name: reply[0], creator: reply[1]
    res.render 'index', data


## AJAX Handlers
app.post '/submit-question', (req, res, next) ->
  username = req.cookies.username
  topic_id = req.body.topic_id
  question = req.body.question

  if not username
    res.send error('username not set')
  else
    redis.incr 'global:nextQuestionId', (err, reply) ->
      question_id = reply
      data = text: question, topic_id: topic_id, creator: username, question_id: question_id, created: (new Date()).getTime()
      redis.hmset 'question:' + reply, data, (err, reply) ->
        redis.lpush 'topic:questions:' + topic_id, question_id, (err, reply) ->
            redis.lpush 'user:questions:' + topic_id, question_id, (err, reply) ->
              # Publish
              io.sockets.in('follow_' + topic_id).emit('question_by_user', username: username)
              io.sockets.in('moderate_' + topic_id).emit('new_question', data)
              # Send Response
              res.send ok("Question submitted successfully.")


## Websockets
io.sockets.on 'connection', (socket) ->
  log 'new connection'

  socket.on 'join_topic', (data) ->
    socket.join 'follow_' + data.topic_id

  socket.on 'moderate_topic', (data) ->
    socket.join 'moderate_' + data.topic_id

  socket.on 'event_start_user_typing', (data) ->
    io.sockets.in('moderate_' + data.topic_id).emit('event_start_user_typing', {username: data.username})

  socket.on 'event_end_user_typing', (data) ->
    io.sockets.in('moderate_' + data.topic_id).emit('event_end_user_typing', {username: data.username})

  socket.on 'get_questions', (data) ->
    topic_id = data.topic_id
    questions = []
    redis.lrange 'topic:questions:' + topic_id, (err, reply) ->
      remaining = reply.length
      redis.hgetall 'topic:' + topic, (err, reply) ->
        questions.push reply
        if remaining == 0
          socket.emit 'questions', questions


## Start the app
app.listen port
console.log 'Chatter server listening on port %d', port
