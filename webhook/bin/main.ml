open Cohttp_lwt_unix
type request_body = {
  event          : string;
  transaction_id : string;
  amount         : string;  
  currency       : string;
  timestamp      : string;
} [@@deriving yojson]

let make_request url json_data =
  let headers = Cohttp.Header.init_with "content-type" "application/json" in
  let body = Cohttp_lwt.Body.of_string json_data in
  let%lwt (resp, body) = Client.post ~headers ~body (Uri.of_string url) in
  let%lwt body_string = Cohttp_lwt.Body.to_string body in
  let status = Cohttp.Response.status resp in
  Lwt.return (status, body_string)

let post_handler request =
  let%lwt body = Dream.body request in
  match Yojson.Safe.from_string body |> request_body_of_yojson with
    | Ok data ->
      Printf.printf "Received event: %s, transaction: %s\n" 
        data.event data.transaction_id;
      
      (* Fazer request para outra API *)
      let%lwt (_status, _response) = make_request 
        "http://127.0.0.1:5001/confirmar" 
        body in
      
      Dream.respond "Success"
    | Error msg ->
        Dream.respond ~status:`Bad_Request ("Invalid JSON: " ^ msg)

let () =
  Dream.run
  ~interface:"0.0.0.0"
  ~port:5000
  @@ Dream.logger
  @@ Dream.router [
        Dream.post "/webhook" post_handler
 
     ]