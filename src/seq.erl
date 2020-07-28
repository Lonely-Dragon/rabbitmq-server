-module('seq').
-compile({no_auto_import,['length'/1]}).
-export([
         append/2,
         average/1,
         averageBy/2,
         %cache/1, % requires mutation
         cast/1,
         choose/2,
         collect/2,
         compareWith/3,
         concat/1,
         contains/2,
         countBy/2,
         delay/1,
         distinct/1,
         distinctBy/2,
         empty/0,
         exactlyOne/1,
         exists/2,
         exists2/3,
         filter/2,
         find/2,
         findIndex/2,
         fold/3,
         forall/2,
         forall2/3,
         groupBy/2,
         head/1,
         init/2,
         initInfinite/1,
         isEmpty/1,
         item/2,
         iter/2,
         iter2/3,
         iteri/2,
         last/1,
         length/1,
         map/2,
         map2/3,
         mapi/2,
         max/1,
         maxBy/2,
         min/1,
         minBy/2,
         nth/2,
         % ofArray/1,
         ofList/1,
         pairwise/1,
         pick/2,
         %readonly/1, % operates on mutable data structures
         reduce/2,
         scan/3,
         singleton/1,
         skip/2,
         skipWhile/2,
         sort/1,
         %sortBy/2,
         sum/1,
         sumBy/2,
         tail/1,
         take/2,
         takeWhile/2,
         %toArray/1,
         toList/1,
         truncate/2,
         tryFind/2,
         tryFindIndex/2,
         tryPick/2,
         unfold/2,
         where/2,
         windowed/2, % returns arrays
         zip/2,
         zip3/3,
         seq/1
        ]).

-type enumerator() :: {list, non_neg_integer(), list()}.

-type seq() :: {seq, enumerator()}.

-export_type([seq/0]).

append(Seq1, Seq2) ->
    {seq, {append, first, seq(Seq1), seq(Seq2)}}.

average(Seq) ->
    averageBy(fun id/1, Seq).

averageBy(F, Seq) ->
    Aggr = fun ({C, Sum}, N) -> {C+1, Sum + N} end,
    {Num, Total} =
        case next(seq(Seq)) of
            finished ->
                % no items in sequence
                throw_arg_exn();
            {Item, Enum} ->
                aggregate(Enum, {1, F(Item)}, Aggr)
        end,
    Total / Num.

distinct(Seq) ->
    distinctBy(fun id/1, Seq).

distinctBy(F, Seq) ->
    {seq, {distinct_by, F, #{}, seq(Seq)}}.

empty() ->
    {seq, {list, []}}.

singleton(Item) ->
    {seq, {list, [Item]}}.

scan(Folder, Initial, Seq) ->
    Scanner = fun ([Last | _] = State, Item) ->
                     Next = Folder(Item, Last),
                     [Next | State]
              end,
    lists:reverse(aggregate(seq(Seq), [Initial], Scanner)).

skip(Num, Seq) ->
    {seq, {skip, Num, seq(Seq)}}.

skipWhile(Pred, Seq) ->
    {seq, {skip_while, Pred, seq(Seq)}}.

sort(Seq) ->
    delay(fun () -> seq(lists:sort(toList(Seq))) end).

sum(Seq) ->
    aggregate(seq(Seq), 0, fun erlang:'+'/2).

sumBy(Proj, Seq) ->
    aggregate(seq(Seq), 0, fun (Acc, V) -> Acc + Proj(V) end).

map(F, Seq) ->
    {seq, {map, F, seq(Seq)}}.

mapi(F, Seq) ->
    {seq, {mapi, F, 0, seq(Seq)}}.

map2(F, Seq1, Seq2) ->
    {seq, {map2, F, seq(Seq1), seq(Seq2)}}.

max(Seq) ->
    reduce_internal(seq(Seq), fun (C, Acc) when C > Acc -> C;
                                  (_, Acc) -> Acc
                              end).


maxBy(Proj, Seq) ->
    {_, Res} = reduce_internal(seq(Seq), fun ({P, _} = Acc, C0) ->
                                                 C = Proj(C0),
                                                 case C > P of
                                                     true -> {C, C0};
                                                     false -> Acc
                                                 end;
                                             (V, C0) ->
                                                 C = Proj(C0),
                                                 P = Proj(V),
                                                 case C > Proj(P) of
                                                     true -> {C, C0};
                                                     false -> {P, V}
                                                 end
                                         end),
    Res.

min(Seq) ->
    reduce_internal(seq(Seq), fun (C, Acc) when C < Acc -> C;
                                  (_, Acc) -> Acc
                              end).
minBy(Proj, Seq) ->
    {_, Res} = reduce_internal(seq(Seq), fun ({P, _} = Acc, C0) ->
                                                 C = Proj(C0),
                                                 case C < P of
                                                     true -> {C, C0};
                                                     false -> Acc
                                                 end;
                                             (V, C0) ->
                                                 C = Proj(C0),
                                                 P = Proj(V),
                                                 case C > Proj(P) of
                                                     true -> {C, C0};
                                                     false -> {P, V}
                                                 end
                                         end),
    Res.
% minBy(Proj, Seq) ->
%     reduce_internal(seq(Seq), fun (C0, Acc) ->
%                                       C = Proj(C0),
%                                       case C < Acc of
%                                           true -> C0;
%                                           false -> Acc
%                                       end
%                               end).

nth(Num, Seq) ->
    item_internal(Num, seq(Seq)).

length(Seq) ->
    aggregate(seq(Seq), 0, fun (C, _) -> C+1 end).

last(Seq) ->
    reduce_internal(seq(Seq), fun (_, I) -> I end).

exists(F, Seq) ->
    find_internal(seq(Seq), F) =/= undefined.

exists2(F, Seq1, Seq2) ->
    find2_internal(F, seq(Seq1), seq(Seq2)) =/= undefined.

exactlyOne(Seq0) ->
    case next(seq(Seq0)) of
        finished ->
            throw_arg_exn();
        {Item, Seq} ->
            case next(Seq) of
                finished ->
                    Item;
                _ ->
                    throw_arg_exn()
            end
    end.

filter(Pred, Seq) ->
    {seq, {filter, Pred, seq(Seq)}}.

where(Pred, Seq) ->
    filter(Pred, Seq).

find(Pred, Seq) ->
    case find_internal(seq(Seq), Pred) of
        undefined ->
            throw_key_not_found_exn();
        {_Index, Item} ->
            Item
    end.

findIndex(Pred, Seq) ->
    case find_internal(seq(Seq), Pred) of
        undefined ->
            throw_key_not_found_exn();
        {Index, _Item} ->
            Index
    end.

fold(Folder, State, Seq) ->
    aggregate(seq(Seq), State, Folder).

forall(Pred, Seq) ->
    case find_internal(seq(Seq), fun (X) -> not Pred(X) end) of
        undefined ->
            true;
        {_Index, _Item} ->
            false
    end.

forall2(Pred, Seq1, Seq2) ->
    case find2_internal(fun (A, B) -> not Pred(A, B) end,
                        seq(Seq1), seq(Seq2)) of
        undefined ->
            true;
        {_Index, _Item} ->
            false
    end.

groupBy(Projection, Seq) ->
    {seq, {delay, fun () -> group_by(Projection, #{}, seq(Seq)) end}}.

head(Seq) ->
    case next(seq(Seq)) of
        finished ->
            throw_arg_exn();
        {Item, _Seq} ->
            Item
    end.

init(Num, Gen) ->
    {seq, {init, 0, Num, Gen}}.

initInfinite(Gen) ->
    {seq, {init_infinite, 0, Gen}}.

isEmpty(Seq) ->
    next(seq(Seq)) =:= finished.

item(Num, Seq) ->
    item_internal(Num, seq(Seq)).

iter(Action, Seq) ->
    ignore = aggregate(Seq, ignore, fun (S, I) ->
                                            Action(I),
                                            S
                                    end),
    unit.

iteri(Action, Seq) ->
    _ = aggregate(Seq, 0, fun (S, I) ->
                                  Action(S, I),
                                  S+1
                          end),
    unit.

iter2(Action, Seq1, Seq2) ->
    _ = toList(map2(Action, Seq1, Seq2)),
    unit.

countBy(F, Seq0) ->
      L = lists:usort(toList(map(F, seq(Seq0)))),
      length(L).

delay(F) ->
    {seq, {delay, F}}.

% cast is effectively a noop
cast(Seq) -> seq(Seq).

choose(Chooser, Seq) ->
    filter(fun(I) ->
                   Chooser(I) =/= undefined
           end, seq(Seq)).

collect(F, Sources) ->
    {seq, {collect, F, seq(Sources)}}.

% Returns the first non-zero result from the comparison function.
% If the end of a sequence is reached it returns a -1 if the first sequence
% is shorter and a 1 if the second sequence is shorter.
compareWith(Comparer, Seq1, Seq2) ->
    Compare = fun Compare(S1, S2) ->
                    case {next(S1), next(S2)} of
                        {finished, finished} -> 0;
                        {finished, _} -> -1;
                        {_, finished} -> 1;
                        {{I1, S1_2}, {I2, S2_2}} ->
                            case Comparer(I1, I2) of
                                0 ->
                                    % they are the same - continue
                                    Compare(S1_2, S2_2);
                                Res ->
                                    Res
                            end
                    end
            end,
    Compare(seq(Seq1), seq(Seq2)).

concat(Sources) ->
    {seq, {concat, undefined, seq(Sources)}}.

contains(Item, Seq) ->
    find_internal(seq(Seq), fun (I) -> I =:= Item end) =/= undefined.

tail(Seq) ->
    {seq, {tail, first, seq(Seq)}}.

take(Num, Seq) ->
    {seq, {take, Num, seq(Seq)}}.

takeWhile(Pred, Seq) ->
    {seq, {take_while, Pred, seq(Seq)}}.

toList(Seq) ->
    enumerate(seq(Seq), []).

truncate(Num, Seq) ->
    {seq, {truncate, Num, seq(Seq)}}.

tryFind(Pred, Seq) ->
    case find_internal(seq(Seq), Pred) of
        undefined ->
            undefined;
        {_Index, Item} ->
            Item
    end.

tryFindIndex(Pred, Seq) ->
    case find_internal(seq(Seq), Pred) of
        undefined ->
            undefined;
        {Index, _Item} ->
            Index
    end.

ofList(List) when is_list(List) ->
    seq(List).

pairwise(Seq) ->
    {seq, {pairwise, undefined, [], seq(Seq)}}.

pick(Picker, Seq) ->
    case pick_internal(seq(Seq), Picker) of
        undefined ->
            throw_key_not_found_exn();
        Item ->
            Item
    end.

reduce(Reducer, Seq) ->
    reduce_internal(seq(Seq), Reducer).

tryPick(Picker, Seq) ->
    pick_internal(seq(Seq), Picker).

unfold(Gen, State) ->
    {seq, {unfold, Gen, State}}.

windowed(Size, Seq) ->
    {seq, {windowed, false, Size, 0,
           array:new(Size, [{fixed, false}]), seq(Seq)}}.

zip(Seq1, Seq2) ->
    {seq, {zip, seq(Seq1), seq(Seq2)}}.

zip3(Seq1, Seq2, Seq3) ->
    {seq, {zip3, seq(Seq1), seq(Seq2), seq(Seq3)}}.

% casts lists (and others) to seq
seq(L) when is_list(L) ->
    {seq, {list, L}};
seq({seq, _} = Seq) ->
    Seq;
seq(Map) when is_map(Map) ->
    {seq, {delay, fun () -> seq(maps:to_list(Map)) end}};
seq({set, Map}) ->
    {seq, {delay, fun () -> seq(maps:keys(Map)) end}};
seq(Seq) ->
    case array:is_array(Seq) of
        true  ->
            {seq, {array, array:size(Seq), 0, Seq}};
        false ->
            throw(argument_exception)
    end.

%%% ------- internal -------

item_internal(0, Seq0) ->
    case next(Seq0) of
        finished ->
            throw_arg_exn();
        {Item, _Seq} ->
            Item
    end;
item_internal(Num, Seq0) ->
    case next(Seq0) of
        finished ->
            throw_arg_exn();
        {_Item, Seq} ->
            item_internal(Num-1, Seq)
    end.

find2_internal(F, Seq1_0, Seq2_0) ->
    case {next(Seq1_0), next(Seq2_0)} of
        {{Item1, Seq1}, {Item2, Seq2}} ->
            case F(Item1, Item2) of
                true ->
                    {Item1, Item2};
                false ->
                    find2_internal(F, Seq1, Seq2)
            end;
        _ ->
            undefined
    end.


find_internal(Enum0, F) ->
    find_internal0(Enum0, 0, F).

find_internal0(Enum0, Index, F) ->
    case next(Enum0) of
        finished ->
            undefined;
        {Item, Enum} ->
            case F(Item) of
                true ->
                    {Index, Item};
                false ->
                    find_internal0(Enum, Index+1, F)
            end
    end.

pick_internal(Enum0, F) ->
    case next(Enum0) of
        finished ->
            undefined;
        {Item0, Enum} ->
            case F(Item0) of
                undefined ->
                    pick_internal(Enum, F);
                Item ->
                    Item
            end
    end.

reduce_internal(Enum0, F) ->
    case next(Enum0) of
        finished ->
            throw_arg_exn();
        {Item, Enum} ->
            aggregate(Enum, Item, F)
    end.

aggregate(Enum0, State, F) ->
    case next(Enum0) of
        finished ->
            State;
        {Item, Enum} ->
            aggregate(Enum, F(State, Item), F)
    end.

enumerate(Enum0, Acc) ->
    case next(Enum0) of
        finished ->
            lists:reverse(Acc);
        {Item, Enum} ->
            enumerate(Enum, [Item | Acc])
    end.

group_by(F, Groups0, Seq0) ->
    case next(Seq0) of
        finished ->
            % reverse each result seq lazily
            maps:fold (fun (Key, Values, Acc) ->
                               [{Key, delay(fun () -> lists:reverse(Values) end)} | Acc]
                       end, [], Groups0);
        {Item, Seq} ->
            Groups = maps:update_with(F(Item),
                                      fun (Items) -> [Item | Items] end,
                                      [Item], Groups0),
            group_by(F, Groups, Seq)
    end.

next({seq, Enum}) ->
    next(Enum);
next({list, [H | Tail]}) ->
    {H, {list, Tail}};
next({list, []}) ->
    finished;
next({map, F, Enum0}) ->
    case next(Enum0) of
        finished -> finished;
        {Item, Enum} ->
            {F(Item), {map, F, Enum}}
    end;
next({mapi, F, Index, Seq0}) ->
    case next(Seq0) of
        finished -> finished;
        {Item, Seq} ->
            {F(Index, Item), {mapi, F, Index+1, Seq}}
    end;
next({map2, F, Seq1_0, Seq2_0}) ->
    case {next(Seq1_0), next(Seq2_0)} of
        {finished, _} -> finished;
        {_, finished} -> finished;
        {{Item1, Seq1}, {Item2, Seq2}} ->
            {F(Item1, Item2), {map2, F, Seq1, Seq2}}
    end;
next({filter, P, Enum}) ->
    do_filter(P, Enum);

next({take, 0, _Enum0}) ->
    finished;
next({take, Num, Enum0}) ->
    case next(Enum0) of
        finished ->
            % not enough elements
            throw_invalid_op_exn();
        {Item, Enum} ->
            {Item, {take, Num-1, Enum}}
    end;

next({truncate, 0, _Enum0}) ->
    finished;
next({truncate, Num, Enum0}) ->
    case next(Enum0) of
        finished ->
            finished;
        {Item, Enum} ->
            {Item, {truncate, Num-1, Enum}}
    end;

next({tail, first, Seq0}) ->
    case next(Seq0) of
        finished ->
            throw_arg_exn();
        {_Item, Seq} ->
            next({tail, rest, Seq})
    end;
next({tail, rest, Seq0}) ->
    case next(Seq0) of
        finished ->
            finished;
        {Item, Seq} ->
            {Item, {tail, rest, Seq}}
    end;

next({take_while, Pred, Enum0}) ->
    case next(Enum0) of
        finished ->
            finished;
        {Item, Enum} ->
            case Pred(Item) of
                true ->
                    {Item, {take_while, Pred, Enum}};
                false ->
                    finished
            end
    end;

next({skip, 0, Enum0}) ->
    case next(Enum0) of
        finished ->
            finished;
        {Item, Enum} ->
            {Item, {skip, 0, Enum}}
    end;
next({skip, Num, Enum0}) ->
    case next(Enum0) of
        finished ->
            throw_invalid_op_exn();
        {_SkippedItem, Enum} ->
            next({skip, Num-1, Enum})
    end;

next({skip_while, Pred, Enum0}) ->
    case next(Enum0) of
        finished ->
            finished;
        {Item, Enum} ->
            case Pred(Item) of
                true ->
                    next({skip_while, Pred, Enum});
                false ->
                    {Item, {skip_while, fun (_) -> false end, Enum}}
            end
    end;

next({pairwise, undefined, [], Seq0}) ->
    case next(Seq0) of
        finished ->
            finished;
        {Item, Seq} ->
            next({pairwise, Item, [], Seq})
    end;
next({pairwise, Last, _Pairs, Seq0}) ->
    case next(Seq0) of
        {Item, Seq} ->
            {{Last, Item}, {pairwise, Item, [], Seq}};
        finished ->
            finished
    end;

next({distinct_by, KeyF, Keys, Seq0}) ->
    case next(Seq0) of
        finished ->
            finished;
        {Item, Seq} ->
            Key = KeyF(Item),
            case maps:is_key(Key, Keys) of
                true ->
                    next({distinct_by, KeyF, Keys, Seq});
                false ->
                    {Item, {distinct_by, KeyF, Keys#{Key => ok}, Seq}}
            end
    end;

next({append, first, Enum0, Seq2}) ->
    case next(Enum0) of
        finished ->
            next({append, second, Enum0, Seq2});
        {Item, Enum} ->
            {Item, {append, first, Enum, Seq2}}
    end;
next({append, second, Seq1Enum, Enum0}) ->
    case next(Enum0) of
        finished -> finished;
        {Item, Enum} ->
            {Item, {append, second, Seq1Enum, Enum}}
    end;

next({concat, undefined, Sources0}) ->
    case next(Sources0) of
        {Enum, Sources} ->
            next({concat, seq(Enum), Sources});
        finished ->
            finished
    end;
next({concat, Enum0, Sources0}) ->
    case next(Enum0) of
        finished ->
            case next(Sources0) of
                {Enum, Sources} ->
                    next({concat, seq(Enum), Sources});
                finished ->
                    finished
            end;
        {Item, Enum} ->
            {Item, {concat, Enum, Sources0}}
    end;

next({init, N, N, _Gen}) ->
    finished;
next({init, Count, Num, Gen}) ->
    {Gen(Count), {init, Count+1, Num, Gen}};

next({init_infinite, Count, Gen}) ->
    {Gen(Count), {init_infinite, Count+1, Gen}};

next({delay, F}) ->
    next(seq(F()));
next({collect, F, {seq, Enum}}) ->
    % add empty "current" list
    next({collect, F, seq([]), Enum});
next({collect, F, Current0, Enum0}) ->
    case next(Current0) of
        finished ->
            case next(Enum0) of
                finished -> finished;
                {Item, Enum} ->
                    ItemsSeq = F(Item),
                    next({collect, F, seq(ItemsSeq), Enum})
            end;
        {Item, Current} ->
            {Item, {collect, F, Current, Enum0}}
    end;

next({unfold, Gen, State0}) ->
    case Gen(State0) of
        undefined ->
            finished;
        {Item, State} ->
            {Item, {unfold, Gen, State}}
    end;
next({zip, Seq1_0, Seq2_0}) ->
    case {next(Seq1_0), next(Seq2_0)} of
        {{Item1, Seq1}, {Item2, Seq2}} ->
            {{Item1, Item2}, {zip, Seq1, Seq2}};
        _ ->
            finished
    end;
next({zip3, Seq1_0, Seq2_0, Seq3_0}) ->
    case {next(Seq1_0), next(Seq2_0), next(Seq3_0)} of
        {{Item1, Seq1}, {Item2, Seq2}, {Item3, Seq3}} ->
            {{Item1, Item2, Item3}, {zip3, Seq1, Seq2, Seq3}};
        _ ->
            finished
    end;
next({windowed, true, Size, Idx, Window00, Seq0}) ->
    case next(Seq0) of
        finished ->
            finished;
        {Item, Seq} ->
            Window0 = array:sparse_foldl(fun (I, V, Acc) ->
                                                 array:set(I-1, V, Acc)
                                         end,
                                        array:new(Size, [{fixed, false}]),
                                        array:reset(0, array:relax(Window00))),
            Window = array:set(Size-1, Item, Window0),
            {Window, {windowed, true, Size, Idx, array:fix(Window), Seq}}
    end;
next({windowed, false, Size, Size, Window, Seq}) ->
    {Window, {windowed, true, Size, Size, array:fix(Window), Seq}};
next({windowed, false, Size, Idx, Window0, Seq0}) ->
    case next(Seq0) of
        finished ->
            finished;
        {Item, Seq} ->
            Window = array:set(Idx, Item, Window0),
            next({windowed, false, Size, Idx+1, Window, Seq})
    end;
next({array, Size, Size, _Array}) ->
    finished;
next({array, Size, Idx, Array}) ->
    {array:get(Idx, Array), {array, Size, Idx+1, Array}}.


do_filter(P, Enum0) ->
    case next(Enum0) of
        finished -> finished;
        {Item, Enum} ->
            case P(Item) of
                true ->
                    {Item, {filter, P, Enum}};
                false ->
                    do_filter(P, Enum)
            end
    end.

id(X) -> X.

throw_arg_exn() ->
    throw({'System.ArgumentException',
           "The input sequence has an insufficient number of elements."}).

throw_key_not_found_exn() ->
    throw({'System.Collections.Generic.KeyNotFoundException', "Key not found"}).

throw_invalid_op_exn() ->
    throw({'System.InvalidOperationException',
           "invalid operation"}).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

basics_test() ->
    EmptySeq = empty(),
    [] = toList(EmptySeq),
    Singleton = singleton(1),
    [1] = toList(Singleton),
    ListSeq = ofList([1,2,3]),
    [1,2,3] = toList(ListSeq),
    MapSeq = map(fun(N) -> N * 2 end, ListSeq),
    [2,4,6] = toList(MapSeq),
    MapSeq2 = map(fun(N) -> N * 2 end, MapSeq),
    [4,8,12] = toList(MapSeq2),
    Filter8 = filter(fun(N) -> N =:= 8 end, MapSeq2),
    [8] = toList(Filter8),
    Filter8_B = where(fun(N) -> N =:= 8 end, MapSeq2),
    [8] = toList(Filter8_B),
    Appended = append(ListSeq, MapSeq),
    [1,2,3,2,4,6] = toList(Appended),
    [1,2,3] = toList(delay(fun () -> ofList([1,2,3]) end)),
    ok.

average_test() ->
    2.0 = average([1.0,2.0,3.0]),
    2.0 = averageBy(fun float/1, [1,2,3]),
    ok.

fold_test() ->
    S = seq([1,2,3]),
    6 = fold(fun (State, T) -> State + T end, 0, S),
    99 = fold(fun (State, T) -> State + T end, 99, []).

sum_test() ->
    S = seq([1,2,3]),
    6 = sum(S),
    0 = sum([]),
    Proj = fun(A, B) -> A + B + B end,
    0 = sumBy(Proj, []),
    0 = sumBy(Proj, []),
    ok.

reduce_test() ->
    Reducer = fun erlang:'+'/2,
    6 = reduce(Reducer, [1,2,3]),
    ?assertException(throw, {'System.ArgumentException', _}, reduce(Reducer, [])),
    ok.

choose_test() ->
    S = seq([1,2,3]),
    [2,3] = toList(choose(fun(1) -> undefined;
                             (N) -> N
                          end, S)).

concat_test() ->
    Sources = seq([seq([1,2,3]), [4,5,6]]),
    [1,2,3,4,5,6] = toList(concat(Sources)).

contains_test() ->
    Seq = seq([1,2,3]),
    true = contains(2, Seq),
    false = contains(5, Seq),
    ok.

find_test() ->
    Seq = seq([1,2,3]),
    2 = find(fun (I) -> I > 1 end, Seq),
    2 = findIndex(fun (I) -> I == 3 end, Seq),
    ?assertException(throw, {'System.Collections.Generic.KeyNotFoundException', _},
                     find(fun (I) -> I > 1 end, [])),
    ?assertException(throw, {'System.Collections.Generic.KeyNotFoundException', _},
                     findIndex(fun (I) -> I > 1 end, [])),
    2 = tryFind(fun (I) -> I > 1 end, Seq),
    2 = tryFindIndex(fun (I) -> I == 3 end, Seq),
    undefined = tryFind(fun (I) -> I > 1 end, []),
    undefined = tryFindIndex(fun (I) -> I == 3 end, []),
    true = exists(fun (I) -> I == 3 end, Seq),
    false = exists(fun (I) -> I == 4 end, Seq),
    Picker = fun (I) when I > 1 -> I;
                 (_) -> undefined
             end,
    2 = pick(Picker, Seq),
    ?assertException(throw, {'System.Collections.Generic.KeyNotFoundException', _},
                     pick(Picker, [])),
    2 = tryPick(Picker, Seq),
    undefined = tryPick(Picker, []),
    ok.

exists2_test() ->
    S1 = [1,2,3],
    S2 = [1,2,3,4],
    Pred = fun(2, 2) -> true;
              (_, _) -> false
           end,
    true = exists2(Pred, S1, S2),
    false = exists2(Pred, S1, []),
    ok.

head_test() ->
    1 = head([1,2,3]),
    ?assertException(throw, {'System.ArgumentException', _}, head([])),
    ok.

tail_test() ->
    [2,3] = toList(tail([1,2,3])),
    ?assertException(throw, {'System.ArgumentException', _}, toList(tail([]))),
    ok.

last_test() ->
    3 = last([1,2,3]),
    ?assertException(throw, {'System.ArgumentException', _}, last([])),
    ok.

isEmpty_test() ->
    false = isEmpty([1,2,3]),
    true = isEmpty(seq([])),
    ok.

iter_test() ->
    Seq = seq([1,2,3]),
    iter(fun(I) -> put(iter_test, I) end, Seq),
    iteri(fun(I, V) -> put(iteri_test, {I, V}) end, Seq),
    iter2(fun(V1, V2) -> put(iter2_test, {V1, V2}) end, Seq, [1,2,3,4]),
    3 = get(iter_test),
    {2, 3} = get(iteri_test),
    {3, 3} = get(iter2_test),
    ok.

init_test() ->
    [0,1,2] = toList(init(3, fun(I) -> I end)),
    [0,1,2] = toList(take(3,initInfinite(fun(I) -> I end))),
    ok.

lists_are_seqs_test() ->
    [1,2,3] = toList([1,2,3]),
    [1,2,3] = toList(delay(fun () -> [1,2,3] end)),
    [1,2] = toList(append([1], [2])),
    ok.

length_test() ->
    3 = length([1,2,3]),
    0 = length(seq([])),
    ok.

collect_test() ->
    [1, -1, 2, -2, 3, -3] = toList(collect(fun (X) -> [X, -X] end, [1,2,3])),
    ok.

compareWith_test() ->
    Comparer = fun (X, X) -> 0;
                   (_, _) -> 99
               end,
    0 = compareWith(Comparer, [1,2,3], [1,2,3]),
    99 = compareWith(Comparer, [1,2,3], [1,3,2]),
    -1 = compareWith(Comparer, [1,2], [1,2,3]),
    1 = compareWith(Comparer, [1,2,3], [1,2]),
    ok.

exactlyOne_test() ->
    ?assertException(throw, {'System.ArgumentException', _}, exactlyOne([])),
    ?assertException(throw, {'System.ArgumentException', _}, exactlyOne([1,2])),
    1 = exactlyOne([1]),
    ok.

take_test() ->
    [1,2] = toList(take(2, [1,2,3])),
    [1,2] = toList(truncate(2, [1,2,3])),
    ?assertException(throw, {'System.InvalidOperationException', _}, toList(take(2, []))),
    [1,2,3] = toList(truncate(5, [1,2,3])),
    [1,2] = toList(takeWhile(fun(I) -> I < 3 end, [1,2,3])),
    ok.

nth_test() ->
    1 = nth(0, [1,2,3]),
    3 = nth(2, [1,2,3]),
    1 = item(0, [1,2,3]),
    3 = item(2, [1,2,3]),
    ?assertException(throw, {'System.ArgumentException', _}, nth(5, [])),
    ?assertException(throw, {'System.ArgumentException', _}, item(5, [])),
    ok.

min_max_test() ->
    1 = min([1,2,3]),
    3 = max([1,2,3]),
    3 = maxBy(fun (X) -> X + X end, [3,1,2,0]),
    1 = minBy(fun (X) -> X + X end, [1,2,3]),
    ?assertException(throw, {'System.ArgumentException', _}, min([])),
    ?assertException(throw, {'System.ArgumentException', _}, max([])),
    ok.

pairwise_test() ->
    [] = toList(pairwise([])),
    [] = toList(pairwise([1])),
    [{1,2}] = toList(pairwise([1,2])),
    [{1,2},{2,3}] = toList(pairwise([1,2,3])),
    [{1,2},{2,3},{3,4}] = toList(pairwise([1,2,3,4])),
    ok.

skip_test() ->
    [3] = toList(skip(2, [1,2,3])),
    [3] = toList(skipWhile(fun(I) -> I < 3 end, [1,2,3])),
    ?assertException(throw, {'System.InvalidOperationException', _}, toList(skip(1, []))),
    ok.

scan_test() ->
    Scanner = fun erlang:'+'/2,
    [0,1,3,6] = scan(Scanner, 0, [1,2,3]),
    [0] = scan(Scanner, 0, []),
    ok.

unfold_test() ->
    Gen = fun (S) when S < 4 -> {S, S + 1};
              (_) -> undefined
          end,
    [1,2,3] = toList(unfold(Gen, 1)),
    ok.

zip_test() ->
    Seq1 = seq([1,2,3]),
    Seq2 = seq([1,2]),
    Seq3 = seq([1,2,3]),
    [{1,1},{2,2}] = toList(zip(Seq1, Seq2)),
    [] = toList(zip([], Seq2)),
    [{1,1,1},{2,2,2}] = toList(zip3(Seq1, Seq2, Seq3)),
    [] = toList(zip3([], Seq2, Seq3)),
    ok.

groupBy_test() ->
    Seq = seq([1,2,3,10]),
    [{low, Low}, {high, High}] =
        toList(groupBy(fun (X) when X < 10 -> low;
                           (_) -> high
                       end, Seq)),

    [10] = toList(High),
    [1,2,3] = toList(Low),
    ok.

mapi_test() ->
    S = [1,2,3],
    [1,3,5] = toList(mapi(fun erlang:'+'/2, S)),
    ok.

map2_test() ->
    S1 = [1,2,3],
    S2 = [1,2,3,4],
    [2,4,6] = toList(map2(fun erlang:'+'/2, S1, S2)),
    ok.

distinct_test() ->
    Seq = [1,2,3,3,2,1],
    [1,2,3] = toList(distinct(Seq)),
    [1,2,3] = toList(distinctBy(fun id/1, Seq)),
    [1,2,3] = toList(distinctBy(fun(N) -> N*N end, Seq)),

    ok.

forall_test() ->
    true = forall(fun(X) -> X < 10 end, [1,2,3]),
    false = forall(fun(X) -> X < 3 end, [1,2,3]),
    true = forall2(fun(A, B) -> A+B < 10 end, [1,2,3], [1,2,3]),
    false = forall2(fun(A, B) -> A+B < 6 end, [1,2,3], [1,2,3]),
    ok.

windowed_test() ->
    Seq = [1,2,3,4],
    [W1, W2, W3] = toList(windowed(2, Seq)),
    [1,2] = array:to_list(W1),
    [2,3] = array:to_list(W2),
    [3,4] = array:to_list(W3),
    [] = toList(windowed(2, [])),
    [] = toList(windowed(2, [1])),
    ok.

countBy_test() ->
    Seq = [1,2,3],
    3 = countBy(fun id/1, Seq),
    1 = countBy(fun(_) -> one end, Seq),
    ok.

sort_test() ->
    Seq = [2,1,3],
    [1,2,3] = toList(sort(Seq)),
    ok.

are_seqs_test() ->
    % arrays
    [1,2,3] = toList(seq(array:from_list([1,2,3]))),
    % maps
    Map = #{one => 1, two => 2},
    [{one, 1}, {two, 2}] = toList(seq(Map)),
    % sets (see SetModule)
    Set = {set, #{1 => ok, 2 => ok}},
    [1,2] = toList(seq(Set)),
    ok.


-endif.
