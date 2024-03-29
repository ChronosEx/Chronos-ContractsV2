// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;
interface IChrNFT {
  function MAX_RESERVE (  ) external view returns ( uint256 );
  function MAX_SUPPLY (  ) external view returns ( uint256 );
  function MINT_PHASE_END (  ) external view returns ( uint256 );
  function MULTISIG (  ) external view returns ( address );
  function NFT_PRICE (  ) external view returns ( uint256 );
  function NFT_PRICE_WL (  ) external view returns ( uint256 );
  function PHASE1_START (  ) external view returns ( uint256 );
  function PHASE2_START (  ) external view returns ( uint256 );
  function PHASE3_START (  ) external view returns ( uint256 );
  function approve ( address to, uint256 tokenId ) external;
  function balanceOf ( address owner ) external view returns ( uint256 );
  function baseURI (  ) external view returns ( string memory );
  function currentRound (  ) external view returns ( uint256 );
  function getApproved ( uint256 tokenId ) external view returns ( address );
  function isApprovedForAll ( address owner, address operator ) external view returns ( bool );
  function isOgUser ( address ) external view returns ( bool );
  function isWhitelisted ( address ) external view returns ( bool );
  function maxMint ( address user ) external view returns ( uint256 max );
  function mint ( uint256 amount ) external;
  function name (  ) external view returns ( string memory);
  function originalMinters ( address ) external view returns ( uint256 );
  function owner (  ) external view returns ( address );
  function ownerOf ( uint256 tokenId ) external view returns ( address );
  function removeOgUser ( address[] memory _users ) external;
  function removeWhitelist ( address[] memory _users ) external;
  function renounceOwnership (  ) external;
  function reserveNFTs ( address[] memory _to, uint256[] memory _amount ) external;
  function reservedAmount (  ) external view returns ( uint256 );
  function safeTransferFrom ( address from, address to, uint256 tokenId ) external;
  function safeTransferFrom ( address from, address to, uint256 tokenId, bytes memory data ) external;
  function setApprovalForAll ( address operator, bool approved ) external;
  function setBaseURI ( string memory baseURI_ ) external;
  function setOgUser ( address[] memory _users ) external;
  function setWhitelist ( address[] memory _users ) external;
  function supportsInterface ( bytes4 interfaceId ) external view returns ( bool );
  function symbol (  ) external view returns ( string memory );
  function tokenByIndex ( uint256 index ) external view returns ( uint256 );
  function tokenOfOwnerByIndex ( address owner, uint256 index ) external view returns ( uint256 );
  function tokenURI ( uint256 tokenId ) external view returns ( string memory );
  function tokensOfOwner ( address _owner ) external view returns ( uint256[] memory );
  function totalSupply (  ) external view returns ( uint256 );
  function transferFrom ( address from, address to, uint256 tokenId ) external;
  function transferOwnership ( address newOwner ) external;
  function withdraw (  ) external;
}
