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

let post_handler req =
  let%lwt body = Dream.body req in
  match Yojson.Safe.from_string body |> request_body_of_yojson with
  | Ok data ->
      (* converte string → float *)
      let amount_float = Float.of_string data.amount in
      let transaction_id = data.transaction_id in

      (* verifica se já existe na lista de duplicados *)
      if contains transaction_id !duplicate_list then (
        (* Se for duplicado, cancela *)
        let cancel_json = Printf.sprintf "{\"transaction_id\":\"%s\"}" transaction_id in
        let%lwt (_status, _response) = make_request 
          "http://127.0.0.1:5001/cancelar" 
          cancel_json in
        Dream.respond ~status:`Bad_Request "Duplicate transaction"
      ) else (
        (* Adiciona na lista *)
        add_to_duplicate_list transaction_id;
        
        (* escolhe endpoint de confirmação ou cancelamento *)
        let endpoint =
          if amount_float <= 0.0 then "/cancelar"
          else "/confirmar"
        in

        (* envia para o serviço externo *)
        let url = "http://127.0.0.1:5001" ^ endpoint in
        let json_to_send = 
          if amount_float <= 0.0 then
            Printf.sprintf "{\"transaction_id\":\"%s\"}" transaction_id
          else
            body
        in
        let%lwt (_status, _response) = make_request url json_to_send in

        (* resposta ao chamador *)
        if amount_float <= 0.0 then
          Dream.respond ~status:`Bad_Request "Invalid amount"
        else
          Dream.respond "Success"
      )

  | Error msg ->
      (* Tenta extrair transaction_id mesmo com JSON inválido *)
      let cancel_json = 
        try
          let partial_json = Yojson.Safe.from_string body in
          match Yojson.Safe.Util.(partial_json |> member "transaction_id" |> to_string_option) with
          | Some txn_id ->
              Printf.sprintf "{\"transaction_id\":\"%s\"}" txn_id
          | None ->
              "{\"transaction_id\":\"parsing_error\"}"
        with
        | _ -> "{\"transaction_id\":\"parsing_error\"}"
      in
      let%lwt (_status, _response) =
        make_request
          "http://127.0.0.1:5001/cancelar"
          cancel_json
      in
      Dream.respond ~status:`Bad_Request ("Invalid JSON: " ^ msg)

let () =
  Dream.run
  ~interface:"0.0.0.0"
  ~port:5000
  @@ Dream.logger
  @@ Dream.router [
        Dream.post "/webhook" post_handler
     ]