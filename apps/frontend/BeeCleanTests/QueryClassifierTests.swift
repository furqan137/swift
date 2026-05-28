import XCTest
@testable import BeeClean

final class QueryClassifierTests: XCTestCase {

    // MARK: - Test Helpers

    /// Create a mock assistant message with photo results
    private func mockAssistantWithResults(assetIds: [String] = ["photo1", "photo2"]) -> AIMessage {
        return AIMessage(
            role: .assistant,
            content: "Here are your photos",
            actions: [],
            assetIds: assetIds,
            state: .complete
        )
    }

    /// Create a mock user message
    private func mockUserMessage(_ text: String) -> AIMessage {
        return AIMessage(
            role: .user,
            content: text,
            actions: [],
            state: .complete
        )
    }

    // MARK: - 1. Greeting Tests (10 cases)

    func testGreeting_Hi() {
        let intent = QueryClassifier.classify("hi", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testGreeting_HiBee() {
        let intent = QueryClassifier.classify("hi bee", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testGreeting_Hey() {
        let intent = QueryClassifier.classify("hey", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testGreeting_HeyBee() {
        let intent = QueryClassifier.classify("hey bee", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testGreeting_Hello() {
        let intent = QueryClassifier.classify("hello", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testGreeting_HiBeeWithPunctuation() {
        let intent = QueryClassifier.classify("HI BEE!!!", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testGreeting_Yo() {
        let intent = QueryClassifier.classify("yo", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testGreeting_GoodMorningBee() {
        let intent = QueryClassifier.classify("good morning bee", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testGreeting_Sup() {
        let intent = QueryClassifier.classify("sup", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testGreeting_Wassup() {
        let intent = QueryClassifier.classify("wassup", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    // MARK: - 2. Capability/Meta Question Tests (10 cases)

    func testMeta_HowAreYou() {
        let intent = QueryClassifier.classify("how are you", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testMeta_HowYouDoing() {
        let intent = QueryClassifier.classify("how you doing", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testMeta_WhatCanYouDo() {
        let intent = QueryClassifier.classify("what can you do", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testMeta_WhoAreYou() {
        let intent = QueryClassifier.classify("who are you", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testMeta_AreYouAI() {
        let intent = QueryClassifier.classify("are you ai", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testMeta_AreYouReal() {
        let intent = QueryClassifier.classify("are you real", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testMeta_HowDoYouWork() {
        let intent = QueryClassifier.classify("how do you work", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testMeta_WhatAreYou() {
        let intent = QueryClassifier.classify("what are you", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testMeta_AreYouHuman() {
        let intent = QueryClassifier.classify("are you human", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testMeta_HowsItGoing() {
        let intent = QueryClassifier.classify("how's it going", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    // MARK: - 3. Acknowledgment Tests (8 cases)

    func testAck_Thanks() {
        let intent = QueryClassifier.classify("thanks", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testAck_Ok() {
        let intent = QueryClassifier.classify("ok", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testAck_Okay() {
        let intent = QueryClassifier.classify("okay", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testAck_Cool() {
        let intent = QueryClassifier.classify("cool", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testAck_Lol() {
        let intent = QueryClassifier.classify("lol", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testAck_Haha() {
        let intent = QueryClassifier.classify("haha", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testAck_Yeah() {
        let intent = QueryClassifier.classify("yeah", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testAck_Nice() {
        let intent = QueryClassifier.classify("nice", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    // MARK: - 4. Photo Search Tests (15 cases)

    func testSearch_FindPicsOfBeach() {
        let intent = QueryClassifier.classify("find pics of beach", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearch_ShowMeMyDog() {
        let intent = QueryClassifier.classify("show me my dog", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearch_PicturesFromLastSummer() {
        let intent = QueryClassifier.classify("pictures from last summer", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearch_Selfies() {
        let intent = QueryClassifier.classify("selfies", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearch_Screenshots() {
        let intent = QueryClassifier.classify("screenshots", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearch_ShowMeFoodPics() {
        let intent = QueryClassifier.classify("show me food pics", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearch_PullUpWeddingPhotos() {
        let intent = QueryClassifier.classify("pull up wedding photos", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearch_GetMePicsOfMom() {
        let intent = QueryClassifier.classify("get me pics of mom", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearch_FindPicsFromNewYork() {
        let intent = QueryClassifier.classify("find pics from new york", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearch_ShowMePicturesOfSunsets() {
        let intent = QueryClassifier.classify("show me pictures of sunsets", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearch_BeachPhotosFrom2019() {
        let intent = QueryClassifier.classify("beach photos from 2019", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearch_FindMyBestFriend() {
        let intent = QueryClassifier.classify("find my best friend", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearch_PicturesOfMyCat() {
        let intent = QueryClassifier.classify("pictures of my cat", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearch_ShowSelfies() {
        let intent = QueryClassifier.classify("show selfies", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearch_FindEuropeanTripPics() {
        let intent = QueryClassifier.classify("find european trip pics", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    // MARK: - 5. Follow-up Tests (12 cases, require previous results)

    func testFollowUp_WhichIsYourFavorite() {
        let previousMessages = [
            mockUserMessage("show me flowers"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("which is your favorite", previousMessages: previousMessages)
        XCTAssertEqual(intent, .followUp)
    }

    func testFollowUp_DoYouPreferPurpleOrYellow() {
        let previousMessages = [
            mockUserMessage("show me flowers"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("do you prefer the purple or yellow", previousMessages: previousMessages)
        XCTAssertEqual(intent, .followUp)
    }

    func testFollowUp_IsntSheCute() {
        let previousMessages = [
            mockUserMessage("find pics of my dog"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("isn't she cute", previousMessages: previousMessages)
        XCTAssertEqual(intent, .followUp)
    }

    func testFollowUp_WhichOneDoYouLike() {
        let previousMessages = [
            mockUserMessage("beach photos"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("which one do you like", previousMessages: previousMessages)
        XCTAssertEqual(intent, .followUp)
    }

    func testFollowUp_WhatDoYouThink() {
        let previousMessages = [
            mockUserMessage("show me my wedding"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("what do you think", previousMessages: previousMessages)
        XCTAssertEqual(intent, .followUp)
    }

    func testFollowUp_WhichOneIsYourFav() {
        let previousMessages = [
            mockUserMessage("college pics"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("which one is your fav", previousMessages: previousMessages)
        XCTAssertEqual(intent, .followUp)
    }

    func testFollowUp_TheFirstOrTheLast() {
        let previousMessages = [
            mockUserMessage("show me my dog"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("the first or the last", previousMessages: previousMessages)
        XCTAssertEqual(intent, .followUp)
    }

    func testFollowUp_DoYouLikeTheSecondOne() {
        let previousMessages = [
            mockUserMessage("beach photos"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("do you like the second one", previousMessages: previousMessages)
        XCTAssertEqual(intent, .followUp)
    }

    func testFollowUp_TheBlurryOneIsFunny() {
        let previousMessages = [
            mockUserMessage("show me my dog"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("the blurry one is funny", previousMessages: previousMessages)
        XCTAssertEqual(intent, .followUp)
    }

    func testFollowUp_WhichIsPrettier() {
        let previousMessages = [
            mockUserMessage("flower pics"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("which is prettier", previousMessages: previousMessages)
        XCTAssertEqual(intent, .followUp)
    }

    func testFollowUp_YourFavoriteOfThese() {
        let previousMessages = [
            mockUserMessage("pics of mom"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("your favorite of these", previousMessages: previousMessages)
        XCTAssertEqual(intent, .followUp)
    }

    func testFollowUp_TheOneWithTheToy() {
        let previousMessages = [
            mockUserMessage("dog pics"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("the one with the toy", previousMessages: previousMessages)
        XCTAssertEqual(intent, .followUp)
    }

    // MARK: - 6. Photo Search After Results (5 cases - should NOT be follow-up)

    func testSearchAfterResults_ShowMeDogs() {
        let previousMessages = [
            mockUserMessage("show me flowers"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("show me dogs", previousMessages: previousMessages)
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearchAfterResults_FindPicsFromCollege() {
        let previousMessages = [
            mockUserMessage("dog pics"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("find pics from college", previousMessages: previousMessages)
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearchAfterResults_PicturesOfFood() {
        let previousMessages = [
            mockUserMessage("beach photos"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("pictures of food", previousMessages: previousMessages)
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearchAfterResults_ShowMeMyMom() {
        let previousMessages = [
            mockUserMessage("wedding pics"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("show me my mom", previousMessages: previousMessages)
        XCTAssertEqual(intent, .photoSearch)
    }

    func testSearchAfterResults_Selfies() {
        let previousMessages = [
            mockUserMessage("flower pics"),
            mockAssistantWithResults()
        ]
        let intent = QueryClassifier.classify("selfies", previousMessages: previousMessages)
        XCTAssertEqual(intent, .photoSearch)
    }

    // MARK: - 7. Edge Cases (10 cases)

    func testEdge_EmptyString() {
        let intent = QueryClassifier.classify("", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testEdge_JustThe() {
        let intent = QueryClassifier.classify("the", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testEdge_JustBee() {
        let intent = QueryClassifier.classify("bee", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testEdge_BeachOneWord() {
        let intent = QueryClassifier.classify("beach", previousMessages: [])
        XCTAssertEqual(intent, .photoSearch)
    }

    func testEdge_EmptyWithNoPreviousMessages() {
        let intent = QueryClassifier.classify("", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testEdge_WhichAloneNoPreviousResults() {
        let intent = QueryClassifier.classify("which", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testEdge_WhatAlone() {
        let intent = QueryClassifier.classify("what", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testEdge_ImBored() {
        let intent = QueryClassifier.classify("i'm bored", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testEdge_ILoveYou() {
        let intent = QueryClassifier.classify("i love you", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testEdge_YoureSoCool() {
        let intent = QueryClassifier.classify("you're so cool", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    // MARK: - Additional Edge Cases

    func testFollowUp_RequiresPreviousResults() {
        // No previous results → should NOT be follow-up even with follow-up signals
        let intent = QueryClassifier.classify("which is your favorite", previousMessages: [])
        XCTAssertEqual(intent, .conversation)
    }

    func testFollowUp_EmptyAssetIds() {
        // Previous message has empty assetIds → should NOT be follow-up
        let previousMessages = [
            mockUserMessage("show me flowers"),
            mockAssistantWithResults(assetIds: [])
        ]
        let intent = QueryClassifier.classify("which is your favorite", previousMessages: previousMessages)
        XCTAssertEqual(intent, .conversation)
    }

    func testFollowUp_OldResults() {
        // Results more than 4 messages ago → should NOT be follow-up
        let previousMessages = [
            mockUserMessage("show me flowers"),
            mockAssistantWithResults(),
            mockUserMessage("thanks"),
            AIMessage(role: .assistant, content: "anytime", actions: [], state: .complete),
            mockUserMessage("what can you do"),
            AIMessage(role: .assistant, content: "I help find photos", actions: [], state: .complete),
            mockUserMessage("cool")
        ]
        let intent = QueryClassifier.classify("which is your favorite", previousMessages: previousMessages)
        XCTAssertEqual(intent, .conversation)
    }
}
