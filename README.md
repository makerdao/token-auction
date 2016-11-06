[![Stories in Ready](https://badge.waffle.io/MakerDAO/token-auction.png?label=ready&title=Ready)](https://waffle.io/MakerDAO/token-auction)
**warning: this contract is still at an early stage and is provided
for reference only. DO NOT use it with real tokens as they may be
permanently lost or stolen.**

# Continuous Splitting Token Auction

This Ethereum contract provides a set of auctions for use with
standard tokens.

The auction was designed for the [Maker] DAO, providing a simple and
passive liquidation mechanism to sell off collateral and debt.
However, the contract is generic and agnostic about its user
provided they adhere to the [token standard][ERC20].

[Maker]: https://makerdao.com
[ERC20]: https://github.com/ethereum/EIPS/issues/20

## Description

The auction provides three auction types - regular *forward* and
*reverse* auctions and a composite *two-way* auction that switches
from forward to reverse once a threshold bid is reached.

In a **forward** auction, bidders compete on the amount they are
willing to pay for the lot.

In a **reverse** auction, bidders compete on the amount of lot they
are willing to receive for a given payment.

A **two-way** auction initially behaves as a forward auction. Once a
given quantity of the buy token has been bid the auction reverses
and becomes a reverse auction.

The auctions are **splitting**. Bidders can bid on a fraction of the
full lot, provided their bid is an increase in valuation. Doing so
*splits* the auction: the previous bidder has their bid quantity
reduced at the same valuation; subsequent bidders can bid on this
reduced quantity or on the new split quantity. There is no limit to
the number of times an auction can be split.

The splittable unit of an auction is an **auctionlet**. Each auction
initially has a single auctionlet. Auctionlets are the object on
which bidders place bids. Splitting an auctionlet produces a new
auctionlet of reduced quantity and reduces the available quantity in
the original auctionlet.

The auctions are **continuous**. The auction beneficiaries are
continually rewarded as new bids are made: by increasing amounts of
the buy token in a forward auction, and by increasing amounts of
forgone sell token in a reverse auction. Highest bidders are
continually rewarded as well: bids are locked once they have existed
for a given time with no higher bids, at which point the highest
bidder can claim their dues.


## Usage

There are three ways of interacting with the auction contract:
[management](#management), [auction creation](#auction-creation),
and [bidding](#bidding). Auction users should subscribe to the
[auction events](#events) to be kept aware of auction creation, new
bids, splits, and reversals.

### Management

Create a new splitting auction manager:

```
import 'token-auction/manager.sol';
manager = new SplittingAuctionManager();
```

Create a new non-splitting auction manager:

```
manager = new AuctionManager();
```

In a non-splitting auction bidders must always bid on the full lot -
they cannot split and bid on a sub-division. The base auctionlet is
the only possible auctionlet, and all bids will happen on this.

The creator of the manager has no special permissions - they
cannot shutdown or withdraw funds from the manager.


### Auction creation

Auction creators connect to an active manager:

```
import 'token-auction/manager.sol';
manager = SplittingAuctionManager(know_manager_address);
```

All created auctions return a pair of `uint (id , base)` that
uniquely identify the new auction and its base auctionlet. These
identifiers are used when bidding and claiming.

Note: you will not be able to use named arguments on auction
creation due to an upstream [solidity issue][name-args-issue].

[named-args-issue]: https://github.com/ethereum/solidity/issues/637

Create a new **forward** auction:

```
var (id, base) = manager.newAuction( beneficiary
                                   , sell_token
                                   , buy_token
                                   , sell_amount
                                   , start_bid
                                   , min_increase
                                   , ttl
                                   )
```

- `address beneficiary` is an address to send auction proceeds to,
  i.e. it will receive `buy_token`.
- `ERC20 buy_token` is the standard token that bidders use to pay with.
- `ERC20 sell_token` is the standard token that the bidders are
  bidding to receive.
- `uint sell_amount` is the amount of `sell_token` to be taken from
  the creator into escrow. The creator must `approve` this amount
  before creating the auction.
- `uint start_bid` is the minimum bid on the auction. The first bid
  must be at least this much plus the minimum increase.
- `uint min_increase` is the integer percentage amount that each bid
  must increase on the last by (in terms of `buy_token`).
- `uint ttl` is the time after the previous bid when a bid will be
  locked and claimable by its highest bidder.


Create a new **reverse** auction:

```
var (id, base) = manager.newReverseAuction( beneficiary
                                          , sell_token
                                          , buy_token
                                          , max_sell_amount
                                          , buy_amount
                                          , min_decrease
                                          , ttl
                                          )
```

Arguments are as for the forward auction with the following extras:

- `uint max_sell_amount` is the maximum amount of `sell_token` that
  the creator is willing to sell, from which bids work downwards.
  This will be taken from the creator on initialisation.
- `uint buy_amount` is the amount of `buy_token` to be paid for the
  full lot, whatever that ends up being.
- `uint min_decrease` is the integer percentage amount that each bid
  must decrease on the last by (in terms of `sell_token`).
- The `beneficiary` receives at most `buy_amount` of the
  `buy_token` and also receives `sell_token` as it is forgone by
  bidders.


Create a new **two-way** auction:

```
var (id, base) = manager.newTwoWayAuction( beneficiary
                                         , sell_token
                                         , buy_token
                                         , sell_amount
                                         , start_bid
                                         , min_increase
                                         , min_decrease
                                         , ttl
                                         , collection_limit
                                         )
```

Arguments are as for the forward and reverse auctions with the
following extras:

- `uint collection_limit` is the total bid quantity of `buy_token`
  at which the auction will reverse.

Auctions creators also have access to the [bidding](#bidding) functions
below.

### Bidding

Auction users connect to an active manager either as a
[creator](#auction-creation) or as a user:

```
import 'token-auction/types.sol';
manager = SplittingAuctionFrontendType(known_manager_address);
```

Users interact with active auctions via `bid` and `claim`.


**Bid** on a non splitting auction:

```
manager.bid(id, bid_amount)
```

- `uint id` is the auctionlet identifier described above.
- `uint bid_amount`

This will throw if the `bid_amount` is not greater than the last bid
by `min_increase`. The `bid_amount` is transferred from the bidder,
so they must `approve` it first. The excess `buy_token` given by the
bid (over the last) is sent directly to the `beneficiary`.


**Bid** on a splitting auction:

```
var (new_id, split_id) = manager.bid(id, bid_amount, split_amount)
```

- `uint split_amount` is the quantity of `sell_token` on which the
  new bid is being made. If the amount is equal to the existing
  quantity, then a regular bid is performed; if it is less, then a
  split bid is performed.

Bidding on a splitting auction returns a pair of identifiers:

- `uint split_id` refers to the auctionlet on which the caller is
  now the highest bidder.
- `uint new_id` refers to the auctionlet on which the previous
  bidder remains as the highest bidder (bidding for a reduced amount
  of `sell_token`).


**Claim** an elapsed auctionlet:

```
manager.claim(id)
```

This will send the `sell_token` associated with `id` to the
highest bidder. `claim` will throw if `ttl` has not elapsed
since the last high bid on `id`.


### Events

**Creation** of a new auction:

```
NewAuction(uint indexed auction_id, uint base_auctionlet_id)
```

- `uint auction_id` is the auction id.
- `uint base_auctionlet_id` is the id of the base auctionlet (on
  which bidding should start)

**Reversal** of a two-way auction:

```
AuctionReversal(uint indexed auction_id)
```

- `uint auction_id` is the id of the auction that has been reversed.


Successful new **bid** on an auctionlet:

```
Bid(uint indexed auctionlet_id)
```

- `uint auctionlet_id` is the id of the auctionlet that has been bid
  on.

Successful **split** of an auctionlet:

```
Split(uint base_id, uint new_id, uint split_id)
```

- `uint base_id` is the id of the auctionlet that has been split
- `uint new_id` is the id of the auctionlet that the previous
  bidder retains.
- `uint split_id` is the id of the new auctionlet that the splitter
  is now the high bidder on.

Note that while `new_id == base_id` at present, this isn't
guaranteed to be the case in the future and you should use `new_id`
as the new identifier.

## Advanced Usage

### Multiple beneficiaries

Forward and two-way auctions can be configured to have multiple
beneficiary addresses, each of which will receive, in turn, a given
payout of auction rewards as higher bids come in.

Create a *multiple beneficiary* auction:

```
var (id, base) = manager.newAuction( beneficiaries
                                   , payouts
                                   , sell_token
                                   , buy_token
                                   , sell_amount
                                   , start_bid
                                   , min_increase
                                   , ttl);
```

- `address[] beneficiaries` is the array of beneficiary addresses
- `uint[] payouts` is the array of corresponding payouts

Note these constraints:

- `beneficiaries` and `payouts` must be equal in length
- `payouts[0]` must be greater than the `start_bid`

The two-way auction is created similarly, with the sum of the
payouts being taken to be the `collection_limit`:

```
var (id, base) = manager.newTwoWayAuction( beneficiaries
                                         , payouts
                                         , sell_token
                                         , buy_token
                                         , sell_amount
                                         , start_bid
                                         , min_increase
                                         , min_decrease
                                         , ttl
                                         );
```

The beneficiaries array is only used in the forward auction or in
the forward part of the two-way auction.


### Reverse auction refund address

In the reverse auction (or the reverse part of the two-way auction),
bidders compete to receive diminishing amounts of the `sell_token`
in return for given `buy_token`. As bids come in, increasing
quantities of the `sell_token` are forgone by bidders.

The default behaviour is to refund this excess `sell_token` to the
(first) beneficiary. It is possible for the auction *creator* to set
the refund address arbitrarily when creating the auction.

Reverse auction:

```
var (id, base) = manager.newReverseAuction( beneficiary
                                          , refund
                                          , sell_token
                                          , buy_token
                                          , max_sell_amount
                                          , buy_amount
                                          , min_decrease
                                          , ttl
                                          )
```

Single beneficiary two-way auction:

```
var (id, base) = manager.newTwoWayAuction( beneficiary
                                         , refund
                                         , sell_token
                                         , buy_token
                                         , sell_amount
                                         , start_bid
                                         , min_increase
                                         , min_decrease
                                         , ttl
                                         , collection_limit
                                         )
```

Multi beneficiary two-way auction:

```
var (id, base) = manager.newTwoWayAuction( beneficiaries
                                         , payouts
                                         , refund
                                         , sell_token
                                         , buy_token
                                         , sell_amount
                                         , start_bid
                                         , min_increase
                                         , min_decrease
                                         , ttl
                                         );
```

- `address refund` is the address that forgone `sell_token` will be
  sent to, continuously.


### Finite duration auction

The default behaviour is for a new auction to persist indefinitely,
until bids have been made for all of the collateral. If there are no
bids then the collateral will remain locked forever.

The forward auction can take an extra argument that determines when
the auction as a whole will expire. After this time, bids will be
rejected and all collateral will be claimable by its last bidder. In
the case of unbid collateral the last bidder is taken to be the
first beneficiary, who will receive the collateral after a call to
`claim`.

Creating a finite-duration auction:

```
var (id, base) = manager.newAuction( beneficiary
                                   , sell_token
                                   , buy_token
                                   , sell_amount
                                   , start_bid
                                   , min_increase
                                   , ttl
                                   , expiration
                                   );
```

- `uint expiration` is the *absolute* time after which the auction
  will be expired, i.e. not relative to the block timestamp on
  creation.


## Gas costs

Approximate and subject to change.

- new SplittingAuctionManager: ~4.3M
- create an auction:           ~500k
- base bid:                    ~130k
- subsequent bids:             ~70k
- base split:                  ~450k
- claim:                       ~75k
- subsequent splits:           ~420k
- bid transition (two-way):    100-150k
- split transition (two-way):  450-470k
