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

let duplicate_list = ref []

let add_to_duplicate_list item =
  duplicate_list := item :: !duplicate_list
let rec contains element = function
  | a::c -> if (a = element) then true else (contains element c)   
  | []   -> false

let extract_transaction_id body =
  try
    Yojson.Safe.(from_string body |> Util.member "transaction_id" |> Util.to_string)
  with
  | _ -> ""

let post_handler req =
  let%lwt body = Dream.body req in
  (* VALIDAÇÃO DE TOKEN *)
  let token_header = Dream.header req "X-Webhook-Token" in
  let expected_token = "meu-token-secreto" in
  match token_header with
  | Some token when token = expected_token ->
      (match Yojson.Safe.from_string body |> request_body_of_yojson with
      | Ok data ->
          let amount_float = Float.of_string data.amount in
          let transaction_id = data.transaction_id in
          if contains transaction_id !duplicate_list then (
            let cancel_json = Printf.sprintf "{\"transaction_id\":\"%s\"}" transaction_id in
            let%lwt (_status, _response) = make_request 
              "http://127.0.0.1:5001/cancelar" 
              cancel_json in
            Dream.respond ~status:`Bad_Request "Duplicate transaction"
          ) else (
            add_to_duplicate_list transaction_id;        
            if amount_float <= 0.0 then (
              let cancel_json = Printf.sprintf "{\"transaction_id\":\"%s\"}" transaction_id in
              let%lwt (_status, _response) = make_request 
                "http://127.0.0.1:5001/cancelar" 
                cancel_json in
              Dream.respond ~status:`Bad_Request "Invalid amount"
            ) else (
              let%lwt (_status, _response) = make_request 
                "http://127.0.0.1:5001/confirmar" 
                body in
              Dream.respond "Success"
            )
          )

      | Error msg ->
          let transaction_id = extract_transaction_id body in
          if transaction_id = "" then (
            Dream.respond ~status:`Bad_Request ("Invalid JSON: " ^ msg)
          ) else (
            let cancel_json = Printf.sprintf "{\"transaction_id\":\"%s\"}" transaction_id in
            let%lwt (_status, _response) = make_request
              "http://127.0.0.1:5001/cancelar"
              cancel_json
            in
            Dream.respond ~status:`Bad_Request ("Invalid JSON: " ^ msg)
          )
      )
  
  | _ ->
      (* Token inválido ou ausente *)
      let transaction_id = extract_transaction_id body in
      if transaction_id = "" then (
        Dream.respond ~status:`Bad_Request "Invalid or missing token"
      ) else (
        let cancel_json = Printf.sprintf "{\"transaction_id\":\"%s\"}" transaction_id in
        let%lwt (_status, _response) = make_request
          "http://127.0.0.1:5001/cancelar"
          cancel_json
        in
        Dream.respond ~status:`Bad_Request "Invalid or missing token"
      )

let () =
  Dream.run
  ~interface:"0.0.0.0"
  ~port:5000
  @@ Dream.logger
  @@ Dream.router [
        Dream.post "/webhook" post_handler
     ]