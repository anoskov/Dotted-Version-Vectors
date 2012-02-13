%% -------------------------------------------------------------------
%%
%% riak_core: Core Riak Application
%%
%% Copyright (c) 2007-2010 Basho Technologies, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

%% @doc A simple Erlang implementation of vector clocks as inspired by Lamport logical clocks.
%%
%% @reference Leslie Lamport (1978). "Time, clocks, and the ordering of events
%% in a distributed system". Communications of the ACM 21 (7): 558-565.
%%
%% @reference Friedemann Mattern (1988). "Virtual Time and Global States of
%% Distributed Systems". Workshop on Parallel and Distributed Algorithms:
%% pp. 215-226

-module(dottedvv).

-author('Ricardo Goncalves <tome@di.uminho.pt>').

-export([fresh/0,descends/2,sync/2,get_counter/2,get_timestamp/2,
	update/3,all_nodes/1,equal/2,increment/2,merge/1,get_max_counter/2]).


-type dottedvv() :: [dvv_entry()].
-type dvv_entry() :: {dvv_id(), {counterM(), timestamp()}} |
					{dvv_id(), {counterM(), counterN(), timestamp()}} .

% ids can have any term() as a name, but they must differ from each other.
-type   dvv_id() :: term().
-type   counterM() :: integer().
-type   counterN() :: integer().
-type   timestamp() :: integer().

% @doc Create a brand new dottedvv.
-spec fresh() -> dottedvv().
fresh() -> [].



% @doc Return true if Va is a direct descendant of Vb, else false -- remember, a dottedvv is its own descendant!
-spec descends(Va :: [dottedvv()], Vb :: [dottedvv()]) -> boolean()
			; (Va :: dottedvv(), Vb :: dottedvv()) -> boolean().
descends(A,B) ->
	A2 = lists:flatten(A),
	B2 = lists:flatten(B),
	case (A2 =:= B2) and (A2 =:= []) of
		true -> false;
		false -> descends1(A,B)
	end.
descends1(_, []) -> true;
descends1(S1=[{_,_}|_],S2) -> descends1([S1],S2);
descends1(S1,S2=[{_,_}|_]) -> descends1(S1,[S2]);
descends1(S1, S2) ->
	descends2(S1,S2).
	%		file:write_file("/Users/ricardoG/Desktop/reii2.txt",lists:flatten(io_lib:format("@2~n A:~p!~n B:~p!~n Res:~p!~n",[S1,S2,Res]))++"!\n",[append]),
	%Res.
%    Trues = [[descends_aux(O1,O2) andalso (descends_aux(O2,O1)==false)
%			|| O2 <- Vb]
%                || O1 <- Va],
%	Trues2 = lists:flatten(Trues),
%	io:format("trues: ~p~n", [Trues2]),
%    lists:foldl(fun(X, Sum) -> X and Sum end, true, Trues2).
%


descends2(_,[]) ->
	true;
descends2([],_) ->
	false;
descends2([H|T],S) ->
	case belongsDelete(H,S) of
		false -> false;
		{true,S2} -> descends2(T,S2)
	end.

belongsDelete(_,[]) ->
	false;
belongsDelete(E,[H|T]) ->
	case descends_aux(lists:flatten(E),lists:flatten(H)) andalso (equal(E,H)==false) of
		true -> {true,T};
		false -> belongsDelete(E,T)
	end.


descends_aux(_, []) ->
    % all dottedvvs descend from the empty dottedvv
    true;
descends_aux(Va, [{IdB, {CtrB, _}}|Vbtail]) ->
    CtrA = 
	case get_counter(IdB, Va) of
	    undefined -> false;
	    {CAm, CAn} -> if CAn == CAm+1 -> 
							CAn;
						true ->
							{CAm, CAn}
					end;
	    CA -> CA
	end,
%	io:format("CA:~p CB:~p~n", [CtrA,CtrB]),
    case CtrA of
	false -> 
		false;
	{CtrAm, _CtrAn} -> 
	    if CtrB > CtrAm->
		    false;
		true ->
		    descends_aux(Va,Vbtail)
	    end;
	_ -> 
	    if
		CtrA < CtrB ->
		    false;
		true ->
		    descends_aux(Va,Vbtail)
	    end
    end;
descends_aux(Va, [{IdB, {CtrBm, CtrBn, T}}|Vbtail]) when CtrBn == CtrBm+1 ->
	descends_aux(Va, ([{IdB, {CtrBn, T}}]++Vbtail));
descends_aux(Va, [{IdB, {CtrBm, CtrBn, _T}}|Vbtail]) ->
    CtrA = 
	case get_counter(IdB, Va) of
	    undefined -> false;
	    {CAm, CAn} -> if CAn == CAm+1 -> 
							CAn;
						true ->
							{CAm, CAn}
					end;
	    CA -> CA
	end,
	
%	io:format("CA:~p CBm:~p CBn:~p~n", [CtrA,CtrBm,CtrBn]),
    case CtrA of
	false -> 
		false;
	{CtrAm, CtrAn} -> 
		if 	(CtrBn == CtrAn) and (CtrAm < CtrBm) ->
				false;
		 	(CtrBn == CtrAn) and (CtrAm >= CtrBm) ->
		    	descends_aux(Va,Vbtail);
		 	CtrBm == CtrAm -> %% CtrBn =/= CtrAn
				false;
	    	CtrBn > CtrAm ->
		    	false;
			true ->
		    	descends_aux(Va,Vbtail)
	    end;
	_ -> 
	    if
		CtrA < CtrBm ->
		    false;
		CtrA < CtrBn ->
		    false;
		true ->
		    descends_aux(Va,Vbtail)
	    end
    end.


merge(S) -> merge2(lists:flatten(S)).
merge2([]) -> [];
merge2(S) ->
	S2 = sets:from_list(S),
	S3 = sets:to_list(S2),
	Old = [[SB || SB <- S3, descends([SA],[SB])] || SA <- S3],
    Old2 = flatten(Old),
    VOld = sets:from_list(Old2),
    VRes = sets:subtract(S2, VOld),
	sets:to_list(VRes).
	


%%%%%%%%%%%%%%%%%%%% sync(S1,S2) -> S
% @doc  Takes two clock sets and returns a clock set. 
%		It returns a set of concurrent clocks, 
%		each belonging to one of the sets, and that 
%		together cover both sets while discarding obsolete knowledge.
-spec sync(Set1 :: [dottedvv()], Set2 :: [dottedvv()]) -> [dottedvv()].
sync(S1=[{_,_}|_],S2) -> sync([S1],S2);
sync(S1,S2=[{_,_}|_]) -> sync(S1,[S2]);
sync(S1,S2) -> 

sync2(S1,S2).

%file:write_file("/Users/ricardoG/Desktop/reii99.txt",lists:flatten(io_lib:format("=============~n A:~p!~n B:~p!~n Res:~p!~n",[S1,S2,Res]))++"!\n",[append]),
%Res.
 
sync2([], []) -> [];
sync2([], S2) -> S2;
sync2(S1, []) -> S1;
sync2(Set1, Set2) ->
	S = Set1 ++ Set2,
	SU = [ sets:to_list(sets:from_list(B)) || B <- S],
	Old = [[S2 || S2 <- SU,
%%		equal(S1,S2) == false,
 		descends(S1,S2)]
                || S1 <- SU],
	%io:format("Old: ~p~n", [Old]),
    Old2 = flatten(Old),
    VOld = sets:from_list(Old2),
    VS = sets:from_list(SU),
	%io:format("Old2: ~p~n", [Old2]),
    VRes = sets:subtract(VS, VOld),
	sets:to_list(VRes).
	

% @private
flatten([]) -> [];
flatten([H|T]) -> H ++ flatten(T).

% @doc Increment DottedVV at Node.
-spec increment(Id :: dvv_id(), Dottedvv :: dottedvv()) -> dottedvv().
increment(Id, Dottedvv) ->
	update(Dottedvv, Dottedvv, Id).

%%%%%%%%%%%%%%%%%%%% update(Sc,Sr,r) -> S
% @doc Update dottedvv at Node.
-spec update(Sc :: [dottedvv()], Sr :: [dottedvv()], IDr :: dvv_id()) -> dottedvv().
update(A,B,Id) -> update2(lists:flatten(A),lists:flatten(B),Id).
update2(Sc, Sr, IDr) ->
%file:write_file("/Users/ricardoG/Desktop/dvv.txt","\tupdate:"++lists:flatten(io_lib:format("\nSc:~p \nSr:~p \nid:~p",[Sc,Sr,IDr]))++"!\n",[append]),
	MaxC = get_max_counter(IDr, Sc),
	MaxR = get_max_counter(IDr, Sr),
%	io:format("maxC ~p  MaxR ~p \nSc:~p!\nSr:~p! \n",[MaxC,MaxR,Sc,Sr]),
	case (MaxC == MaxR) of
		true -> 
			[ {Id, get_max_counter_time(Id, Sc)} || Id <- all_nodes(Sc) , Id =/= IDr] ++
			[ {IDr, {MaxR + 1 , timestamp()}} ]; 
		false ->
			[ {Id, get_max_counter_time(Id, Sc)} || Id <- all_nodes(Sc) , Id =/= IDr] ++
			[ {IDr, {MaxC, MaxR + 1 , timestamp()}} ]
		end.
%	io:format("get_max_counter: ~p, ~p!", [get_max_counter(IDr, Sc), get_max_counter(IDr, Sr)]),
%file:write_file("/Users/ricardoG/Desktop/dvv.txt","\tupdate:"++lists:flatten(io_lib:format("RES:~p",[Res]))++"!\n",[append]),



%%%%%%%%%%%%%%%%%%%% ids(X) -> [id]
% @doc Return the list of all nodes that have ever incremented dottedvv.
-spec all_nodes(Dottedvv :: dottedvv()) -> [dvv_id()]
			;  ([Dottedvv :: dottedvv()]) -> [dvv_id()].
			
all_nodes([]) -> [];
all_nodes({X,_}) -> [X];
all_nodes(Dottedvv=[{_,_}|_]) ->
    sets:to_list(sets:from_list([X || {X,{_,_}} <- Dottedvv] ++ [X || {X,{_,_,_}} <- Dottedvv])).



%%%%%%%%%%%%%%%%%%%% [S]r -> max(Sr)
% @private
-spec get_max_counter(Id :: dvv_id(), [Dottedvv :: dottedvv()]) -> counterM().
%	io:format("get_max_counter2: ~p, ~p -> ~p!", [Id, Dottedvv,  get_counter(Id, Dottedvv)]),
get_max_counter(A,B) -> get_max_counter_aux(A,B,0).
get_max_counter_aux(_, [], Acc) -> 
	%io:format("yey0\n",[]), 
	Acc;
get_max_counter_aux(Id, [{Id2,{_M,N,_T}}|Tail], Acc) when Id =:= Id2 ->
	%io:format("yey1\n",[]), 
	case N < Acc of
		true -> get_max_counter_aux(Id,Tail,Acc);
		false -> get_max_counter_aux(Id,Tail,N)
	end;
get_max_counter_aux(Id, [{Id2,{M,_T}}|Tail], Acc) when Id =:= Id2 -> 
	%io:format("yey2\n",[]), 
	case M < Acc of
		true -> get_max_counter_aux(Id,Tail,Acc);
		false -> get_max_counter_aux(Id,Tail,M)
	end;
get_max_counter_aux(Id, [_|Tail], Acc) -> 
	%io:format("yey3\n",[]), 
	get_max_counter_aux(Id,Tail,Acc).
	
	
	
get_max_counter_time(A,B) -> get_max_counter_time_aux(A,B,{0,timestamp()}).
get_max_counter_time_aux(_, [], Acc) -> 
	%io:format("yey0\n",[]), 
	Acc;
get_max_counter_time_aux(Id, [{Id2,{_M,N,T}}|Tail], Acc={N2,_T2}) when Id =:= Id2 ->
	%io:format("yey1\n",[]), 
	case N < N2 of
		true -> get_max_counter_time_aux(Id,Tail,Acc);
		false -> get_max_counter_time_aux(Id,Tail,{N,T})
	end;
get_max_counter_time_aux(Id, [{Id2,{M,T}}|Tail], Acc={N2,_T2}) when Id =:= Id2 -> 
	%io:format("yey2\n",[]), 
	case M < N2 of
		true -> get_max_counter_time_aux(Id,Tail,Acc);
		false -> get_max_counter_time_aux(Id,Tail,{M,T})
	end;
get_max_counter_time_aux(Id, [_|Tail], Acc) -> 
	%io:format("yey3\n",[]), 
	get_max_counter_time_aux(Id,Tail,Acc).
	


% @doc Get the counter value in dottedvv set from Node.
-spec get_counter(Id :: dvv_id(), Dottedvv :: dottedvv()) -> counterM() | {counterM(),counterN()} | undefined.
get_counter(Id, Dottedvv) ->
    case proplists:get_value(Id, Dottedvv) of
	{M, _} -> M;
	{M, N, _} -> {M,N};
	undefined -> undefined
    end.


% @doc Get the timestamp value in a dottedvv set from Node.
-spec get_timestamp(Node :: dvv_id(), Dottedvv :: dottedvv()) -> timestamp() | undefined.
get_timestamp(Node, Dottedvv) ->
    case proplists:get_value(Node, Dottedvv) of
	{_, _, TS} -> TS;
	{_, TS} -> TS;
	undefined -> undefined
    end.

% @private
timestamp() ->
    calendar:datetime_to_gregorian_seconds(erlang:universaltime()).




% @doc Compares two dottedvvs for equality.
-spec equal(Dottedvv :: [dottedvv()], Dottedvv :: [dottedvv()]) -> boolean().
equal([],[]) -> true;
equal(S1=[{_,_}|_],S2) -> equal([S1],S2);
equal(S1,S2=[{_,_}|_]) -> equal(S1,[S2]);
equal(S1,S2) -> 
%file:write_file("/Users/ricardoG/Desktop/dvv.txt","\equal_sets:"++lists:flatten(io_lib:format("\nS1:~p \nS2:~p",[S1,S2]))++"!\n",[append]),
equal2(S1,S2).


equal2([],[]) ->
	true;
equal2([],_) ->
	false;
equal2(_,[]) ->
	false;
equal2([H|T],S) ->
	case belongsDelete2(H,S) of
		false -> false;
		{true,S2} -> equal2(T,S2)
	end.
	
	
belongsDelete2(_,[]) ->
	false;
belongsDelete2(E,[H|T]) ->
	case equal3(E,H) of
		true -> {true,T};
		false -> belongsDelete2(E,T)
	end.

equal3(VA,VB) ->
%file:write_file("/Users/ricardoG/Desktop/dvv.txt","\tequal:"++lists:flatten(io_lib:format("\nVa:~p \nVb:~p",[VA,VB]))++"!\n",[append]),
    VSet1 = sets:from_list(VA),
    VSet2 = sets:from_list(VB),
    case sets:size(sets:subtract(VSet1,VSet2)) > 0 of
        true -> false;
        false ->
            case sets:size(sets:subtract(VSet2,VSet1)) > 0 of
                true -> false;
                false -> true
            end
    end.



