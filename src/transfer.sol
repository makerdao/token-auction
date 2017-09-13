pragma solidity ^0.4.15;

import './types.sol';
import './util.sol';

// Methods for transferring funds into and out of the auction manager
// and between bidders and beneficiaries.
//
// Warning: these methods call code outside of the auction, via the
// transfer methods of the buying / selling token. Bear this in mind if
// the auction allows arbitrary tokens to be added, as they could be
// malicious.
//
// These methods take Auction(lets) as arguments to allow them to do
// complex settlement logic. However, their access to the auction is
// read-only - they cannot write to storage.
contract TransferUser is Assertive, MathUser, AuctionType {
    function takeFundsIntoEscrow(Auction auction)
        internal
    {
        assert(auction.selling.transferFrom(auction.creator, this, auction.sell_amount));
    }
    function payOffLastBidder(Auction auction, Auctionlet auctionlet,
                              address new_bidder, address prev_bidder, uint how_much)
        internal
    {
        assert(auction.buying.transferFrom(new_bidder, prev_bidder, how_much));
    }
    function settleExcessBuy(Auction auction, address bidder, uint excess_buy)
        internal
    {
        require(auction.buying.transferFrom(bidder, auction.beneficiary, excess_buy));
    }
    function settleExcessSell(Auction auction, uint excess_sell)
        internal
    {
        assert(auction.selling.transfer(auction.refund, excess_sell));
    }
    function settleBidderClaim(Auction auction, Auctionlet auctionlet)
        internal
    {
        assert(auction.selling.transfer(auctionlet.last_bidder, auctionlet.sell_amount));
    }
    function settleReclaim(Auction auction)
        internal
    {
        assert(auction.selling.transfer(auction.creator, auction.unsold));
    }
}

