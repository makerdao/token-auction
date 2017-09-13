pragma solidity ^0.4.15;

contract EventfulAuction {
    event LogBid(uint indexed auctionlet_id);
    event LogSplit(uint base_id, uint new_id, uint split_id);
    event LogAuctionReversal(uint indexed auction_id);
}

contract EventfulManager {
    event LogNewAuction(uint indexed id, uint base_id);
}

