open Test_helpers

let tests = [
  "process", [
    "basic", `Quick, begin fun () ->
      Luv.Process.spawn "echo" ["echo"; "-n"]
      |> check_success_result "spawn"
      |> Luv.Handle.close;

      run ()
    end;

    "on_exit", `Quick, begin fun () ->
      let called = ref false in

      let result =
        Luv.Process.spawn "echo" ["echo"; "-n"]
            ~on_exit:begin fun process ~exit_status ~term_signal:_ ->

          Alcotest.(check int) "exit status" 0 exit_status;
          Luv.Handle.close process;
          called := true
        end
      in
      check_success_result "spawn" result |> ignore;

      run ();

      Alcotest.(check bool) "called" true !called
    end;

    "redirect to fd", `Quick, begin fun () ->
      let parent_end, child_end = Unix.(socketpair PF_UNIX SOCK_STREAM) 0 in
      let child_end_raw : int = Obj.magic child_end in
      let parent_end_file : Luv.File.t = Obj.magic parent_end in
      let parent_end = Luv.Pipe.init () |> check_success_result "pipe init" in
      Luv.Pipe.open_ parent_end parent_end_file |> check_success "pipe open";

      Luv.Process.(spawn
        "echo" ["echo"; "-n"; "foo"]
        ~redirect:[inherit_fd ~fd:stdout ~from_parent_fd:child_end_raw])
      |> check_success_result "spawn"
      |> Luv.Handle.close;

      Unix.close child_end;

      let finished = ref false in

      Luv.Stream.read_start parent_end begin fun result ->
        Luv.Handle.close parent_end;
        check_success_result "read" result
        |> snd
        |> Alcotest.(check int) "byte count" 3;
        finished := true
      end;

      run ();

      Alcotest.(check bool) "finished" true !finished
    end;

    "redirect to stream", `Quick, begin fun () ->
      let parent_end, child_end = Unix.(socketpair PF_UNIX SOCK_STREAM) 0 in
      let parent_end_file : Luv.File.t = Obj.magic parent_end in
      let parent_end = Luv.Pipe.init () |> check_success_result "pipe init" in
      Luv.Pipe.open_ parent_end parent_end_file |> check_success "pipe open";
      let child_end_file : Luv.File.t = Obj.magic child_end in
      let child_end = Luv.Pipe.init () |> check_success_result "pipe init" in
      Luv.Pipe.open_ child_end child_end_file |> check_success "pipe open";

      Luv.Process.(spawn
        "echo" ["echo"; "-n"; "foo"]
        ~redirect:[inherit_stream ~fd:stdout ~from_parent_stream:child_end])
      |> check_success_result "spawn"
      |> Luv.Handle.close;

      Luv.Handle.close child_end;

      let finished = ref false in

      Luv.Stream.read_start parent_end begin fun result ->
        Luv.Handle.close parent_end;
        check_success_result "read" result
        |> snd
        |> Alcotest.(check int) "byte count" 3;
        finished := true
      end;

      run ();

      Alcotest.(check bool) "finished" true !finished
    end;

    "create pipe", `Quick, begin fun () ->
      let parent_end = Luv.Pipe.init () |> check_success_result "pipe init" in

      Luv.Process.(spawn
        "echo" ["echo"; "-n"; "foo"]
        ~redirect:[to_new_pipe ~fd:stdout ~to_parent_pipe:parent_end ()])
      |> check_success_result "spawn"
      |> Luv.Handle.close;

      let finished = ref false in

      Luv.Stream.read_start parent_end begin fun result ->
        Luv.Handle.close parent_end;
        check_success_result "read" result
        |> snd
        |> Alcotest.(check int) "byte count" 3;
        finished := true
      end;

      run ();

      Alcotest.(check bool) "finished" true !finished
    end;

    "set environment variable", `Quick, begin fun () ->
      let parent_end = Luv.Pipe.init () |> check_success_result "pipe init" in

      Luv.Process.(spawn
        "printenv" ["printenv"; "FOO"]
        ~environment:["FOO", "foobar"]
        ~redirect:[to_new_pipe ~fd:stdout ~to_parent_pipe:parent_end ()])
      |> check_success_result "spawn"
      |> Luv.Handle.close;

      let finished = ref false in

      Luv.Stream.read_start parent_end begin fun result ->
        Luv.Handle.close parent_end;
        check_success_result "read" result
        |> snd
        |> Alcotest.(check int) "byte count" 7;
        finished := true
      end;

      run ();

      Alcotest.(check bool) "finished" true !finished
    end;

    "inherit environment", `Quick, begin fun () ->
      Unix.putenv "FOO" "foobar";
      Alcotest.(check string) "FOO" "foobar" (Unix.getenv "FOO");

      let parent_end = Luv.Pipe.init () |> check_success_result "pipe init" in

      Luv.Process.(spawn
        "printenv" ["printenv"; "FOO"]
        ~redirect:[to_new_pipe ~fd:stdout ~to_parent_pipe:parent_end ()])
      |> check_success_result "spawn"
      |> Luv.Handle.close;

      let finished = ref false in

      Luv.Stream.read_start parent_end begin fun result ->
        Luv.Handle.close parent_end;
        check_success_result "read" result
        |> snd
        |> Alcotest.(check int) "byte count" 7;
        finished := true
      end;

      run ();

      Alcotest.(check bool) "finished" true !finished;

      Unix.putenv "FOO" ""
    end;

    "clear environment", `Quick, begin fun () ->
      Unix.putenv "FOO" "foobar";
      Alcotest.(check string) "FOO" "foobar" (Unix.getenv "FOO");

      let parent_end = Luv.Pipe.init () |> check_success_result "pipe init" in
      let exit_code = ref None in

      let result =
        Luv.Process.(spawn
          "printenv" ["printenv"; "FOO"]
          ~environment:[]
          ~redirect:[to_new_pipe ~fd:stdout ~to_parent_pipe:parent_end ()]
          ~on_exit:begin fun process ~exit_status ~term_signal:_ ->
            Luv.Handle.close process;
            exit_code := Some exit_status
          end)
      in
      check_success_result "spawn" result |> ignore;

      let finished = ref false in

      Luv.Stream.read_start parent_end begin fun result ->
        Luv.Handle.close parent_end;
        check_error_result "read" Luv.Error.eof result;
        finished := true
      end;

      run ();

      Alcotest.(check (option int)) "exit code" (Some 1) !exit_code;
      Alcotest.(check bool) "finished" true !finished;

      Unix.putenv "FOO" ""
    end;

    "set working directory", `Quick, begin fun () ->
      let child_working_directory = Filename.dirname (Sys.getcwd ()) in

      let parent_end = Luv.Pipe.init () |> check_success_result "pipe init" in

      Luv.Process.(spawn
        "pwd" ["pwd"]
        ~working_directory:child_working_directory
        ~redirect:[to_new_pipe ~fd:stdout ~to_parent_pipe:parent_end ()])
      |> check_success_result "spawn"
      |> Luv.Handle.close;

      let finished = ref false in

      Luv.Stream.read_start parent_end begin fun result ->
        Luv.Handle.close parent_end;
        let data, length = check_success_result "read" result in
        Alcotest.(check int)
          "length" (String.length child_working_directory) (length - 1);
        Luv.Bigstring.sub data ~offset:0 ~length:(length - 1)
        |> Luv.Bigstring.to_string
        |> Alcotest.(check string) "data" child_working_directory;
        finished := true
      end;

      run ();

      Alcotest.(check bool) "finished" true !finished
    end;

    "inherit working directory", `Quick, begin fun () ->
      let parent_working_directory = Sys.getcwd () in

      let parent_end = Luv.Pipe.init () |> check_success_result "pipe init" in

      Luv.Process.(spawn
        "pwd" ["pwd"]
        ~redirect:[to_new_pipe ~fd:stdout ~to_parent_pipe:parent_end ()])
      |> check_success_result "spawn"
      |> Luv.Handle.close;

      let finished = ref false in

      Luv.Stream.read_start parent_end begin fun result ->
        Luv.Handle.close parent_end;
        let data, length = check_success_result "read" result in
        Alcotest.(check int)
          "length" (String.length parent_working_directory) (length - 1);
        Luv.Bigstring.sub data ~offset:0 ~length:(length - 1)
        |> Luv.Bigstring.to_string
        |> Alcotest.(check string) "data" parent_working_directory;
        finished := true
      end;

      run ();

      Alcotest.(check bool) "finished" true !finished
    end;

    "failure", `Quick, begin fun () ->
      Luv.Process.spawn "./nonexistent" ["nonexistent"]
      |> check_error_result "spawn" Luv.Error.enoent
    end;

    "failure handle leak", `Quick, begin fun () ->
      no_memory_leak begin fun _ ->
        Luv.Process.spawn "./nonexistent" ["nonexistent"]
        |> check_error_result "spawn" Luv.Error.enoent;

        run ()
      end
    end;

    "failure callback leak", `Quick, begin fun () ->
      let called = ref false in

      no_memory_leak begin fun _ ->
        Luv.Process.spawn "./nonexistent" ["nonexistent"]
            ~on_exit:begin fun _ ~exit_status:_ ~term_signal:_ ->

          called := true
        end
        |> check_error_result "spawn" Luv.Error.enoent;

        run ()
      end;

      Alcotest.(check bool) "not called" false !called
    end;

    "kill", `Quick, begin fun () ->
      let received_signal = ref None in

      let result =
        Luv.Process.spawn "cat" ["cat"]
            ~on_exit:begin fun process ~exit_status:_ ~term_signal ->

          Luv.Handle.close process;
          received_signal := Some term_signal
        end
      in
      let process = check_success_result "spawn" result in

      Luv.Process.kill process Luv.Signal.sigint
      |> check_success "kill";

      run ();

      Alcotest.(check (option int)) "term_signal"
        (Some Luv.Signal.sigint) !received_signal
    end;

    "pid, kill_pid", `Quick, begin fun () ->
      let received_signal = ref None in

      let result =
        Luv.Process.spawn "cat" ["cat"]
            ~on_exit:begin fun process ~exit_status:_ ~term_signal ->

          Luv.Handle.close process;
          received_signal := Some term_signal
        end
      in
      let process = check_success_result "spawn" result in

      Luv.Process.(kill_pid ~pid:(pid process)) Luv.Signal.sigint
      |> check_success "kill";

      run ();

      Alcotest.(check (option int)) "term_signal"
        (Some Luv.Signal.sigint) !received_signal
    end;
  ]
]
