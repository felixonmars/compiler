module Ren.Stage.Lex exposing (..)

{-| -}

-- IMPORTS ---------------------------------------------------------------------

import Parser exposing ((|.), (|=), Parser)
import Ren.Data.Token as Token exposing (Token)
import Set exposing (Set)



--


lex : String -> Result () (List Token)
lex source =
    Parser.run stream source
        |> Result.map collect
        |> Result.mapError (\_ -> ())


collect : List Token -> List Token
collect tokens =
    let
        go tok ( acc, list ) =
            case ( tok, acc ) of
                ( Token.Comment a, Just (Token.Comment b) ) ->
                    ( Just <| Token.Comment <| a ++ "\n" ++ b, list )

                ( Token.Comment _, Just b ) ->
                    ( Just tok, b :: list )

                ( Token.Comment _, Nothing ) ->
                    ( Just tok, list )

                ( Token.Unknown a, Just (Token.Unknown b) ) ->
                    ( Just <| Token.Unknown <| a ++ b, list )

                ( Token.Unknown _, Just b ) ->
                    ( Just tok, b :: list )

                ( Token.Unknown _, Nothing ) ->
                    ( Just tok, list )

                ( _, Just b ) ->
                    ( Nothing, tok :: b :: list )

                ( _, Nothing ) ->
                    ( Nothing, tok :: list )
    in
    List.foldr go ( Nothing, [] ) tokens
        |> (\( acc, list ) -> Maybe.map ((::) >> (|>) list) acc |> Maybe.withDefault list)



-- PARSERS ---------------------------------------------------------------------


stream : Parser (List Token)
stream =
    Parser.succeed Basics.identity
        |. Parser.spaces
        |= many (token |. Parser.spaces)
        |. Parser.end


token : Parser Token
token =
    Parser.oneOf
        [ number
        , string
        , keyword
        , comment
        , operator
        , symbol
        , identifier
        , Parser.chompIf (Basics.always True)
            |> Parser.getChompedString
            |> Parser.map Token.Unknown
        ]


number : Parser Token
number =
    Parser.number
        { int = Just (Basics.toFloat >> Token.Number)
        , hex = Nothing
        , octal = Nothing
        , binary = Nothing
        , float = Just Token.Number
        }
        |> Parser.backtrackable


string : Parser Token
string =
    let
        go cs =
            Parser.oneOf
                [ Parser.succeed (\c -> Parser.Loop (c :: cs))
                    |. Parser.token "\\"
                    |= Parser.oneOf
                        [ Parser.map (\_ -> "\n") (Parser.token "n")
                        , Parser.map (\_ -> "\t") (Parser.token "t")
                        , Parser.map (\_ -> "\u{000D}") (Parser.token "r")
                        ]
                , Parser.token "\""
                    |> Parser.map (\_ -> Parser.Done (String.join "" (List.reverse cs)))
                , Parser.chompWhile isUninteresting
                    |> Parser.getChompedString
                    |> Parser.map (\c -> Parser.Loop (c :: cs))
                ]

        isUninteresting char =
            char /= '\\' && char /= '"'
    in
    Parser.succeed Token.String
        |. Parser.token "\""
        |= Parser.loop [] go


comment : Parser Token
comment =
    Parser.succeed ()
        |. Parser.token "//"
        |. Parser.chompUntilEndOr "\n"
        |> Parser.getChompedString
        |> Parser.map Token.Comment


keyword : Parser Token
keyword =
    fromSet Token.keywords Parser.keyword Token.keyword
        |> Parser.backtrackable


symbol : Parser Token
symbol =
    fromSet Token.symbols Parser.symbol Token.symbol
        |> Parser.backtrackable


operator : Parser Token
operator =
    fromSet Token.operators Parser.symbol Token.operator
        |> Parser.backtrackable


identifier : Parser Token
identifier =
    Parser.oneOf
        [ Parser.variable
            { start = \c -> Char.isUpper c
            , inner = \c -> Char.isAlphaNum c || c == '_'
            , reserved = Set.empty
            }
        , Parser.variable
            { start = \c -> Char.isLower c
            , inner = \c -> Char.isLower c || Char.isDigit c || c == '_'
            , reserved = Token.keywords
            }
        ]
        |> Parser.andThen
            (\s ->
                case Token.identifier s of
                    Just id ->
                        Parser.succeed id

                    Nothing ->
                        Parser.problem ""
            )
        |> Parser.backtrackable



-- UTILS -----------------------------------------------------------------------


fromSet : Set String -> (String -> Parser ()) -> (String -> Maybe a) -> Parser a
fromSet options parser f =
    let
        parseOption s =
            parser s
                |> Parser.getChompedString
                |> Parser.map f
                |> Parser.andThen (Maybe.map Parser.succeed >> Maybe.withDefault (Parser.problem ""))
    in
    Set.toList options
        |> List.sortBy (String.length >> (*) -1)
        |> List.map parseOption
        |> Parser.oneOf


many : Parser a -> Parser (List a)
many parser =
    Parser.loop []
        (\xs ->
            Parser.oneOf
                [ Parser.succeed (\x -> x :: xs)
                    |= parser
                    |> Parser.map Parser.Loop
                , Parser.succeed xs
                    |> Parser.map List.reverse
                    |> Parser.map Parser.Done
                ]
        )
