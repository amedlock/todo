import os, tables, strutils, sequtils, parseopt, algorithm,times, terminal;

# Todo.txt utility

let usageText = """
Usage:
  todo topic? command?

Where 'command' is one of:
  list <options>  : lists all todos in current file, empty command assumes "list"
  add "text"      : Adds a new todo item to the current list, will create new todo.txt
  start <int>     : Starts the todo at index <int>
  done <int>      : Marks a todo item as complete, timestamps the item 
  pause <int>     : Marks an in-progress task as paused/blocked
  optional <int>  : Marks an item as optional
  format          : Shows todo.txt file format (for manual editing)

topic has the form: @name , this means to see all tasks for cooking you would type
todo @cooking list

options can be:  -<letters> which limits todos listed to specific statuses
  -d = Show tasks which are done 
  -n = Show new tasks
  -s = Show started (in progress) tasks
  -o = Show optional tasks
  -p = Show paused tasks

Note that the default is to list all incomplete statuses
"""

let layoutText = """
Todo.txt files have one line per task, with tasks having the following format:
<status> <date?> <description>

<status> is one of:
+ This marks a new task
- This marks a task which has been started
X This is a task which has been completed, usually has a timestamp
? This is an optional task
! This marks a task as blocked or paused

<date> is optional and in format YYYY-MM-DD

Inside the description @topic marks the task as belonging to a specific topic
"""

type
  Status = enum
    Unstarted
    Started
    Optional
    Paused
    Done
    Other
  Cmd = object
    action : string
    topic : string
    index : int
    text : string
  Todo = ref object
    desc: string
    index: int
    status : Status


proc display( t : Todo ) =
  styledWrite( stdout, fgYellow, ($t.index).alignLeft(3) )
  var color = fgBlue
  if t.status==Started:
    color = fgGreen
  elif t.status==Paused:
    color = fgRed
  elif t.status==Done:
    color = fgMagenta
  styledWrite( stdout, color, ($t.status).alignLeft(20) )
  styledWriteLine( stdout, fgWhite, t.desc )
  resetAttributes()

proc update_status( t : var Todo, s : Status ) =
  if t.status==s:
    echo("Task($1) is already in status $2".format( t.desc, s ))
  elif t.status==Done:
    echo("Task($1) is completed. Cannot change status.".format( t.desc ))
  else:
    t.status = s
    if s==Done:
      let timestamp = now().format("yyyy-MM-dd")
      t.desc = "$1 $2".format( timestamp, t.desc )

proc has_topic( line : string, name: string ) : bool =
  let key = "@$1".format( name.toLowerAscii )
  return line.toLowerAscii.find( key ) >= 0   # will match a partial as well TODO

proc add_todo( todos: var seq[Todo], s: Status, line: string ) =
  var x = Todo()
  x.status = s
  x.index = todos.len+1
  x.desc = line
  todos.add( x )

proc find_todo( todos: seq[Todo], index: int ) : Todo =
  if index < 1 or index > todos.len:
    echo("Task index is invalid")
    quit(-1)
  return todos[index-1]


let taskMarkers = {'+': Unstarted, '-': Started, 'X': Done, '?':Optional, '!': Paused }.toTable;

proc marker( s : Status ): char =
  for ch, s2 in taskMarkers:
    if s2==s:
      result = ch

proc parse_todo(line:string, todos: var seq[Todo] ) =
  if line.isNilOrWhitespace:
    return
  var x = line.strip()
  if not taskMarkers.hasKey( x[0] ):
    echo("Ignored invalid line in todo:$1".format( x ))
  # TODO parse timestamp here
  var t = new(Todo)
  t.status = taskMarkers[x[0]]
  t.desc = x.substr(1, x.high).strip()
  t.index = todos.len+1
  todos.add( t )


proc read_file(): seq[Todo] =
  result = @[]
  if existsFile("todo.txt"):
    let f = open( "todo.txt", FileMode.fmRead)
    var index = 1
    for line in f.readAll.splitLines:
      parse_todo( line, result )
    f.close()

proc write_file( todos: seq[Todo], filename: string = "todo.txt") =
  let ordering = [Started, Unstarted, Paused, Optional, Done]
  let sorted = todos.sortedByIt( ordering.find(it.status) )
  let f = open(filename, fmWrite)
  for t in sorted:
    let m = t.status.marker
    if taskMarkers.hasKey(m):
      f.write( "$1 $2\n".format( m, t.desc ) )
  f.close()


let actionStatus = {"start": Started, "done": Done, "pause": Paused, "option": Optional }.toTable;

proc handle( cmd: Cmd, todos: var seq[Todo]) =
  if cmd.action in ["list", "ls"]:
    if cmd.topic.len>0:
      echo("Listing tasks with topic:$1".format(cmd.topic))
      for t in todos.filterIt( it.desc.has_topic(cmd.topic) ):
        t.display()
    else:
      for t in todos:
        t.display()
    return
  elif cmd.action == "add":
    todos.add_todo( Status.Unstarted, cmd.text.strip(true, true,{'"'}).strip() )
    todos.write_file()
  elif cmd.action in actionStatus:
    let status = actionStatus[cmd.action]
    var t = todos.find_todo( cmd.index )
    t.update_status( status )
    todos.write_file()
  elif cmd.action == "delete":
    var t = todos.find_todo( cmd.index )
    todos = todos.filterIt( it!=t )
    todos.write_file()
  else:
    echo("Unknown command:" & cmd.action )
    quit(-1)
      

proc parse_topic( opt: var OptParser ) : string = 
  opt.next()
  if opt.kind==cmdArgument:
    result = opt.key.strip(true, false, {'@'})

proc parse_index( action:string,  opt: var OptParser ) : int = 
  opt.next()
  if opt.kind==cmdArgument and opt.key.isDigit():
    result = opt.key.parseInt()
  else:
    echo("The command $1 requires an index as second argument ".format(action))
    quit(-1)
  

let shortcuts = {"a": "add", "l": "list", "ls": "list", "?": "help", "h":"help" }.toTable;

proc parse_cmd() : Cmd = 
  result.action = "list"
  result.topic = ""
  result.index = -1
  var opt = initOptParser()
  while true:
    opt.next()
    if opt.kind==cmdEnd: 
      break
    if opt.kind==cmdArgument:
      var key = opt.key
      if shortcuts.hasKey( key ): 
        key = shortcuts[key]
      if key=="help":
        echo usageText
        quit(QuitSuccess)
      elif key=="format":
        echo layoutText
        quit(QuitSuccess)
      elif key.startsWith("@"):
        result.topic = key.substr(1, opt.key.high )
        opt.next()
      elif key=="list":
        result.action = "list"
        result.topic = parse_topic( opt )
        break
      elif key=="add":
        result.action = key
        result.text = opt.cmdLineRest
        break
      elif key in ["option", "start", "done", "pause", "delete"]:
        result.action = key
        result.index = parse_index( key, opt )
        break
      else:
        echo("Unknown command:" & opt.key )
        quit(-1)


var cmd = parse_cmd() 
var todos = read_file()
handle( cmd, todos )

