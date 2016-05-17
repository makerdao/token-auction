# Auctions for Maker [![Build Status](https://api.travis-ci.org/rainbeam/token-auction.svg?branch=master)](https://travis-ci.org/rainbeam/token-auction)

## Motivation

Maker has several core mechanisms that require a way to sell / buy
tokens.  The 'debt auction', 'collateral auction' and 'buy and burn'
are all referenced in the whitepaper - each of them is currently
envisaged as a token auction.

Along with feeds, auctions are how Maker interacts with the external
world. Profit seeking agents (Keepers), will use the auctions to
acquire / release tokens to sell / buy on the open market. The
advantage that auctions have over a direct market connection is that
they relieve Maker of the need to be market aware.


## Usage

The CDP mechanism uses auctions at several points.

For example, consider a CDP with 110 ETH and 100 DAI debt based on a
liquidation ratio of 120% and a penalty ratio of 105%. This CDP is
below its liquidation point and can therefore be liquidated.

A call to `liquidate` begins the liquidation process. The
following happend simultaneously:

1. Maker issues emergency debt to cover the 100 dai, which puts the
   CDP into a zombie state.

2. Maker begins the 'debt auction', in which it tries to acquire the
   100 dai for as little MKR as possible. MKR is released by calling 
   `TokenSupplyManger.demand`. This process is started in
   'DaiSettler.settle' when credit < emergency_debt.
   The auction here is a *Reverse Auction*

3. Maker begins the 'collateral auction', in which it seeks to get
   as much dai as possible for the CDP collateral. This is triggered
   directly by `CDPEngineController.liquidate`.
   The auction here is a *Two way auction*, which starts as a
   regular forward auction and switches to a reverse auction if a
   target is reached (105 dai for all the collateral).


In the forward part of the collateral auction, Maker is seeking to
gain as much dai as possible for the collateral, up to a maximum of
105 dai. In the the reverse part, Maker sees who is willing to take
the least collateral in return for 105 dai. Any excess collateral is
refunded to the CDP owner. All dai income is sent to *buy and burn*.

The two way collateral auction seeks to get the best price for the
CDP owner following liquidation.

In buy and burn, Maker seeks to acquire maximum MKR for fixed dai
via a regular *forward auction*. This process starts in
`DaiSettler.settle` when  credit > emergency_debt.


## Auction types

There are three auction types described:

1. *Forward Auction* - sell the full lot at the highest price.

2. *Reverse Auction* - sell as little of the lot as possible, at a
   fixed price.

3. *Two-way Auction* - begin as a forward auction but switch to
   reverse if a target bid is reached.


## Splitting

The described auctions can also be *splitting* auctions. The
splitting auction allows for bidding on subdivisions of a
homogeneous lot.

A splitting auction starts as a single lot, which can be split into
sub auctions called 'auctionlets'. If a bidder is willing to pay a
higher price for a fraction of the lot, they 'split' the auctionlet.
The old bidder retains their bid at the old price, but on less
quantity. The new bidder is now the highest bidder on an auctionlet
containing the quantity that they were willing to bid for.

Any individual auctionlet behaves like a regular forward / reverse
auction.

For example, say there are two auctionlets - a1, a2 - both bidding
on 50% of the full lot at prices p1 < p2. A new bidder is willing to
pay p3 > p2 for 75% of the full lot. To get this they would bid(a1, p3) 
and split(a2, 0.5, p3) to realise the full 75%.
