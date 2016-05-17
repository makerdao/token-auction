import 'erc20/erc20.sol';

import 'assertive.sol';

// This contract contains a number of Auctions, each of which is
// *splittable*.  The splittable unit of an Auction is an Auctionlet,
// which has all of the Auctions properties but allows for bidding on a
// subset of the full Auction lot.
contract SplittableAuctionManager is Assertive {
    struct Auction {
        address beneficiary;
        ERC20 selling;
        ERC20 buying;
        uint min_bid;
        uint min_increase;
        uint sell_amount;
        uint claimable;
        uint claimed;
        uint expiration;
    }
    struct Auctionlet {
        uint     auction_id;
        address  last_bidder;
        uint     last_bid;
        uint     quantity;
        bool     claimed;
    }

    mapping(uint => Auction) _auctions;
    uint _last_auction_id;

    mapping(uint => Auctionlet) _auctionlets;
    uint _last_auctionlet_id;

    // Create a new auction, with specific parameters.
    // Bidding is done through the auctions associated auctionlets,
    // of which there is one initially.
    function newAuction( address beneficiary
                        , ERC20 selling
                        , ERC20 buying
                        , uint sell_amount
                        , uint min_bid
                        , uint min_increase
                        , uint duration
                        )
        returns (uint auction_id)
    {
        Auction memory a;
        a.beneficiary = beneficiary;
        a.selling = selling;
        a.buying = buying;
        a.sell_amount = sell_amount;
        a.min_bid = min_bid;
        a.min_increase = min_increase;
        a.expiration = getTime() + duration;

        var received_lot = selling.transferFrom(beneficiary, this, sell_amount);
        assert(received_lot);

        _auctions[++_last_auction_id] = a;

        Auctionlet memory base_auctionlet;
        base_auctionlet.auction_id = _last_auction_id;
        base_auctionlet.quantity = sell_amount;

        _auctionlets[++_last_auctionlet_id] = base_auctionlet;

        return _last_auction_id;
    }
    function getAuction(uint id) constant
        returns (address, ERC20, ERC20, uint, uint, uint, uint)
    {
        Auction a = _auctions[id];
        return (a.beneficiary, a.selling, a.buying,
                a.sell_amount, a.min_bid, a.min_increase, a.expiration);
    }
    function getAuctionlet(uint id) constant
        returns (uint, address, uint, uint)
    {
        Auctionlet a = _auctionlets[id];
        return (a.auction_id, a.last_bidder, a.last_bid, a.quantity);
    }
    // bid on a specifc auctionlet
    function bid(uint auctionlet_id, uint bid_how_much) {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];
        assert(bid_how_much >= A.min_bid);
        assert(bid_how_much >= (a.last_bid + A.min_increase));

        var expired = A.expiration <= getTime();
        assert(!expired);

        var received_bid = A.buying.transferFrom(msg.sender, this, bid_how_much);
        assert(received_bid);

        var returned_bid = A.buying.transfer(a.last_bidder, a.last_bid);
        assert(returned_bid);

        a.last_bidder = msg.sender;
        a.last_bid = bid_how_much;
        A.claimable += bid_how_much;
    }
    // bid on a specific quantity of an auctionlet
    function split(uint auctionlet_id, uint quantity, uint bid_how_much)
        returns (uint)
    {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        assert(quantity < a.quantity);

        // check that there is a relative increase in value
        // n.b avoid dividing by a.last_bid as it could be zero
        var valuation = (bid_how_much * a.quantity) / quantity;
        assert(valuation > a.last_bid);

        var received_bid = A.buying.transferFrom(msg.sender, this, bid_how_much);
        assert(received_bid);

        var new_quantity = a.quantity - quantity;
        //@log old quantity: `uint a.quantity`
        //@log new_quantity: `uint new_quantity`

        // n.b. associativity important because of truncating division
        var new_bid = (a.last_bid * new_quantity) / a.quantity;
        //@log last_bid: `uint a.last_bid`
        //@log new_bid: `uint new_bid`

        a.quantity = new_quantity;
        a.last_bid = new_bid;

        Auctionlet memory sa;

        sa.auction_id = a.auction_id;
        sa.last_bidder = msg.sender;
        sa.quantity = quantity;
        sa.last_bid = bid_how_much;

        _auctionlets[++_last_auctionlet_id] = sa;

        return _last_auctionlet_id;
    }
    // Parties to an auction can claim their take. The auction creator
    // (the beneficiary) can claim across an entire auction. Individual
    // auctionlet high bidders must claim per auctionlet.
    function claim(uint id) {
        if (msg.sender == _auctions[id].beneficiary) {
            _claim_winnings(id);
        } else {
            _claim_proceedings(id, msg.sender);
        }
    }
    // claim the existing bids from all auctionlets connected to a
    // specific auction
    function _claim_winnings(uint auction_id) internal {
        var A = _auctions[auction_id];
        var settled = A.buying.transfer(A.beneficiary, A.claimable);
        assert(settled);

        A.claimed = A.claimable;
        A.claimable = 0;
    }
    // claim the proceedings from an auction for the highest bidder
    function _claim_proceedings(uint auctionlet_id, address claimer) internal {
        var a = _auctionlets[auctionlet_id];
        var A = _auctions[a.auction_id];

        assert(claimer == a.last_bidder);

        var expired = A.expiration <= getTime();
        assert(expired);

        assert(!a.claimed);

        var settled = A.selling.transfer(a.last_bidder, a.quantity);
        assert(settled);

        a.claimed = true;
    }
    function getTime() public constant returns (uint) {
        return block.timestamp;
    }
}
