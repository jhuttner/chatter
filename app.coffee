## Imports

express = require 'express'
redis = require('redis').createClient()
server = require('http').Server(app)
io = require('socket.io')(server)
port = 3001
redis_db = TODO


## Configuration

redis.select redis_db

app = express()
app.use express.bodyParser()
app.configure () ->
  app.set 'views', __dirname + '/views'
  app.set 'view engine', 'jade'
  app.use express.bodyParser()
  app.use express.methodOverride()  
  app.use app.router
  app.use expres.static(__dirname + '/public')


## Helper functions

log = (s) ->
  console.log s

error = (s) ->
  response = {response: {status: "ERROR", msg: s}}
  JSON.dumps response
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
  username = req.username
  res.cookie 'username', username
  res.redirect '/home'

app.get '/logout', (req, res, next) ->
  res.clearCookie 'username'
  res.redirect '/login'

app.get '/home', (req, res, next) ->
  username = req.cookie 'username'
  if not username
    res.redirect '/login?err=requires_login'
  else
    # 1. Get the topics started by the user.
    redis.lrange 'user:topics:' + username, 0, -1, (err, reply) ->
      topic_ids = reply
      user_topics = []
      user_questions = {}
      remaining = topic_ids.length

      for topic_id in topic_ids
        redis.hgetall 'topic:'+topic_id,  (err, reply) ->
          user_topics.push reply
          remaining -= 1
          if remaining == 0

            # 2. Get the questions asked by the user.
            redis.lrange 'user:questions:' + username, 0, -1, (err, reply) ->
              user_question_ids = reply
              remaining = user_question_ids.length
              for question_id in question_ids
                redis.hgetall 'question:' + question_id, (err, reply) ->
                  user_questions.push reply
                  remaining -= 1
                  if remaining == 0
                    data =
                      user_topics: user_topics
                      user_questions: user_questions
                      username: username
                    res.render 'home', data

app.post '/create-topic', (req, res, next) ->
  username = req.cookie 'username'
  topic_name = req.body 'topic_name'
  if not username
    res.redirect '/login?error=requires_login'
  else
    redis.sadd 'global:topicNames', topic_name, (err, reply) ->
      if reply == 0
        res.send error('topic name already in use.  try again')
      else
        redis.incr 'global:nextTopicId', (err, reply) ->
          topic_id = reply
          data = name: topic_name, creator: username, created: (new Date()).getTime()
          redis.hmset 'topic:' + topic_id, data, (err, reply) ->
            redis.lpush 'user:topics:' + username, topic_id, (err, reply) ->
              res.redirect '/moderate-topic/' + topic_id

app.get '/moderate-topic/:topic_id', (req, res, next) ->
  username = req.cookie 'username'
  topic_id = req.params.topic_id
  if not username
    res.redirect '/login?error=requires_login'
  else
    redis.hget 'topic:' + topic_id, 'creator', (err, reply) ->
      if reply != username
        res.redirect '/login?error=user_not_moderator'
      else
        redis.hget 'topic:' + topic_id, 'name', (e, reply) ->
          data = topic_name: reply
          res.render 'moderate-topic', data

app.get '/join-topic/:topic_id', (req, res, next) ->
  topic_id = req.params.topic_id
  redis.hmget 'topic:' + topid_id, ['name', 'creator'], (err, reply) ->
    data = name: reply[0], creator: reply[1]
    res.render 'join-topic', data


## AJAX Handlers

app.post '/submit-question', (req, res, next) ->
  username = req.cookie 'username'
  topic_id = req.body 'topic_id'
  question = req.body 'question'

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
              io.sockets.in('follow-' + topic_id).emit('question_by_user', username)
              io.sockets.in('moderate-' + topic_id).emit('question', data)
              # Send Response
              res.send ok("Question submitted successfully.")


## Websockets

io.sockets.on 'connection', (socket) ->
  log 'new connection'

  socket.on 'join-topic', (data) ->
    socket.join 'follow-' + data.topic_id

  socket.on 'moderate-topic', (data) ->
    socket.join 'moderate-' + data.topic_id

  socket.on 'event-user-typing', (data) ->
    io.sockets.in('moderate-' + data.topic_id).emit('event-user-typing', {username: data.username})

app.listen port
console.log ('Chatter server listening on port %d', port)
