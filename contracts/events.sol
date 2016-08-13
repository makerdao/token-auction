contract EventfulAuction {
    event Bid(uint indexed auctionlet_id, uint bid_price);
    event Split(uint base_id, uint new_id, uint split_id);
    event AuctionReversal(uint indexed auction_id);
}

contract EventfulManager {
    event NewAuction(uint indexed id, uint base_id);
}

