const { ethers } = require("hardhat")
const { expect } = require("chai");
const chai = require("chai");
const { loadFixture } = require("ethereum-waffle");
const { BigNumber } = require("ethers");

const { BN }  = require('bn.js');
chai.use(require('chai-bn')(BN));

const { setupHeavyEntriesUpdateTests, setupAccounts } = require("./fixtures.js");
const { mintAndDeposit, multiplier, sync, increaseTime, MATURITY_INCREMENT, MATURITY_PRECISION } = require("./helpers.js");
const { testError } = require("./test_helpers.js");

describe("MaGaugeV2Upgradeable: Heavy entries update test", function () {

    it("New contract was deployed", async function() {
        const { _token, maNFT } = await loadFixture(setupHeavyEntriesUpdateTests);
        expect(await maNFT.totalSupply()).to.equal(0);
    });

    it("Weights are correct in between deposits and after sync", async function() {
        const { _token, maNFT } = await loadFixture(setupHeavyEntriesUpdateTests);
        const { acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10 } = await loadFixture(setupAccounts);

        let accounts = [acc1, acc2, acc3, acc4, acc5, acc6, acc7, acc8, acc9, acc10];

        let expectedLPSupply = BigNumber.from(0);

        let count = 300; // amount of deposits made before sync post 6 weeks
        let maxDelta = 3600; // the max delta between deposits
        let syncDelay = MATURITY_INCREMENT * 2; // delay after deposits
        let times = 3; // how many times the test should be repeated

        let depositAmounts = [];
        let deltas = [];

        let positions = [];
        let entries = [];

        // prepare test data for executing deposits
        for (var i = 0; i < count * times; i++) {
            depositAmounts[i] = BigNumber.from("1000000000000000000").mul(Math.floor(Math.random() * 1000) + 1);
            deltas[i] = Math.floor(Math.random() * maxDelta);
        }

        console.log("Creating " + count + " deposits with frequency up to " + maxDelta + "seconds");

        let lastUpdateTime = 0;

        for (var currentTime = 0; currentTime < times; currentTime++) {
            for (var i = count * currentTime; i < count * (currentTime + 1); i++) {
                // making a deposit
                var amount = BigNumber.from(depositAmounts[i]);
                let account = accounts[Math.floor(Math.random() * (accounts.length - 1))];
                let id = await mintAndDeposit(account, amount, _token, maNFT);
    
                console.log("Deposited " + amount + " to NFT id " + id);
    
                expectedLPSupply = expectedLPSupply.add(amount);
    
                // checking LP balance validity
                expect(await maNFT.lpTotalSupply()).to.equal(expectedLPSupply);
                expect(await maNFT.lpBalanceOfmaNFT(id)).to.equal(amount);
    
                // checking individual weights validity
                let updateTime = await maNFT._positionEntries(id);
                entries[i] = updateTime;
                positions[i] = id;
    
                lastUpdateTime = updateTime;
    
                var expectedTotal = BigNumber.from("0");
                for (var j = 0; j < positions.length; j++) {
                    let expectedWeight = BigNumber.from(depositAmounts[j]).mul(multiplier(entries[j], lastUpdateTime));
                    expectedTotal = expectedTotal.add(expectedWeight);
                    let actualWeight = await maNFT.maNFTWeight(positions[j]);
    
                    expect(actualWeight).to.equal(expectedWeight);
                }
    
                // checking total weight validity
                let actualTotalWeight = await maNFT.totalWeight();
    
                // it is expected to have an error in weight increment due to the maturity precision
                let error = testError(expectedTotal, actualTotalWeight);
                console.log("Exp weight = " + expectedTotal);
                console.log("Act weight = " + actualTotalWeight);
                console.log("Error = " + error);
    
                console.log("----")
    
                console.log("Increasing time by " + deltas[i]);
    
                await increaseTime(deltas[i]);
    
                console.log("----")
            };
    
            // execute sync without new deposits with a large delay from last sync
            let preSyncLPSupply = await maNFT.lpTotalSupply();
            let preSyncWeight = await maNFT.totalWeight();
    
            console.log("Current LP Supply = " + preSyncLPSupply);
            console.log("Current Total Weight = " + preSyncWeight);
    
            console.log("Increasing the time by " + syncDelay);
    
            await increaseTime(syncDelay);
            await sync(acc1, maNFT);
    
            console.log("Post-deposits check");
    
            lastUpdateTime = await maNFT._lastTotalWeightUpdateTime();
    
            // check individual positions weights
            var expectedTotal = BigNumber.from("0");
            for (var j = 0; j < positions.length; j++) {
                let expectedWeight = BigNumber.from(depositAmounts[j]).mul(multiplier(entries[j], lastUpdateTime));
                expectedTotal = expectedTotal.add(expectedWeight);
    
                let actualWeight = await maNFT.maNFTWeight(positions[j]);
    
                expect(actualWeight).to.equal(expectedWeight);
            }
    
            // check total weight
            let actualTotalWeight = await maNFT.totalWeight();

            // it is expected to have an error in total weight due to the maturity precision
            // and the lack of calculation precision when calculating multiplier
            let error = testError(expectedTotal, actualTotalWeight);

            // if the delay was more than 6 weeks, all posisions must have the max multiplier
            if (syncDelay >= 2 * MATURITY_INCREMENT) {
                let expectedWeightFromLPSupply = BigNumber.from(preSyncLPSupply).mul(BigNumber.from(MATURITY_PRECISION).mul(3));
    
                expect(BigNumber.from(actualTotalWeight)).to.be.equal(expectedWeightFromLPSupply);
            }
            
            console.log("Exp weight = " + expectedTotal);
            console.log("Act weight = " + actualTotalWeight);
            console.log("Error = " + error);
            console.log("----")
        }

    });
});