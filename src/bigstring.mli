type t = (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

val create : int -> t
val length : t -> int
val get : t -> int -> char
val set : t -> int -> char -> unit
val sub : t -> offset:int -> length:int -> t
val blit : source:t -> destination:t -> unit
val fill : t -> char -> unit
val unsafe_get : t -> int -> char
val unsafe_set : t -> int -> char -> unit

val to_string : t -> string
val to_bytes : t -> bytes
val from_string : string -> t
val from_bytes : bytes -> t

val blit_to_bytes : t -> bytes -> destination_offset:int -> unit
val blit_from_bytes : t -> bytes -> source_offset:int -> unit
val blit_from_string : t -> string -> source_offset:int -> unit

(* DOC How to use sub, sub+blit. *)
