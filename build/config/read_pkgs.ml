let usage () =
  prerr_endline
    {|usage: read_pkgs.exe [options] VARNAME < pkgs.txt

The Package.Ver file is read from the standard input.

Prints an OCaml `let VARNAME = [(pkgname, pkgver); ...]` let binding of all the
Package.Ver to the standard output.

Options:
--only-global-install - Only show Package.Ver that have the global-install directive
--only-global-compile - Only show Package.Ver that have the global-compile directive
|}

let badarg s =
  usage ();
  prerr_endline s;
  exit 2

module State = struct
  type directive = Global_install | Global_compile

  type t = { directives : directive list }

  let create () = { directives = [] }

  let of_string = function
    | "global-install" -> Global_install
    | "global-compile" -> Global_compile
    | s -> failwith (Printf.sprintf "Unsupported directive: %s" s)

  let directive_to_string = function
    | Global_compile -> "Global_compile"
    | Global_install -> "Global_install"

  let to_string { directives } =
    Printf.sprintf "[%s]"
      (String.concat ";" (List.map directive_to_string directives))
end

let parseline ~filter line state =
  let line' = String.trim line in
  match line' with
  | "" ->
      (* empty line *)
      state
  | _ when String.length line' >= 2 && line'.[0] = '#' && line'.[1] = ' ' ->
      (* comment line *)
      state
  | _
    when String.length line' >= 3
         && line'.[0] = '#'
         && line'.[1] = '#'
         && line'.[2] = ' ' ->
      (* directive line *)
      let directive =
        String.trim @@ String.sub line' 3 (String.length line' - 3)
      in
      { State.directives = State.of_string directive :: state.State.directives }
  | _ ->
      ((* Package.Ver *)
       let terms = String.split_on_char '.' line' in
       match terms with
       | [] ->
           failwith
             "A Package.Ver name must have a period (.) character, like \
              fmt.0.9.0"
       | pkg :: version_terms ->
           if filter state then
             let version = String.concat "." version_terms in
             Printf.printf "  (\"%s\", \"%s\", %s);\n" (String.escaped pkg)
               (String.escaped version) (State.to_string state));
      { State.directives = [] }

let () =
  (* parsing *)
  let varname = ref "" in
  let anon name = varname := name in
  let filter = ref (fun _state -> true) in
  Arg.parse
    [
      ( "--only-global-install",
        Unit
          (fun () ->
            filter :=
              fun { State.directives } ->
                List.mem State.Global_install directives),
        "Only show packages with the [## global-install] directive" );
      ( "--only-global-compile",
        Unit
          (fun () ->
            filter :=
              fun { State.directives } ->
                List.mem State.Global_compile directives),
        "Only show packages with the [## global-compile] directive" );
    ]
    anon "read_pkgs";
  if String.equal !varname "" then badarg "Missing VARNAME argument";
  (* printing *)
  Printf.printf "let %s = [\n" !varname;
  let state = ref (State.create ()) in
  try
    while true do
      state := parseline ~filter:!filter (input_line stdin) !state
    done
  with End_of_file ->
    Printf.printf "]\n";
    flush stdout
