#!/usr/bin/swift

import Foundation

// API request function
func requestChatGPT(prompt: String, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
    let url = URL(string: "https://api.openai.com/v1/engines/text-davinci-003/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  
    let requestBody: [String: Any] = [
        "temperature": 0.7,
        "prompt": prompt,
        "max_tokens": 2000,
        "top_p": 1,
        "frequency_penalty": 0,
        "presence_penalty": 0,
        "n": 1,
        "stop": ["\"\"\""]
    ]
  
    guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody, options: []) else {
        completion(.failure(NSError(domain: "Invalid request body", code: -1, userInfo: nil)))
        return
    }
  
    request.httpBody = httpBody

    let sessionConfig = URLSessionConfiguration.default
    sessionConfig.timeoutIntervalForRequest = 600.0
    sessionConfig.timeoutIntervalForResource = 600.0
    let session = URLSession(configuration: sessionConfig)

    session.dataTask(with: request) { data, response, error in
        if let error = error {
            completion(.failure(error))
            return
        }
      
        guard let data = data else {
            completion(.failure(NSError(domain: "No response data", code: -1, userInfo: nil)))
            return
        }
      
        guard let jsonResponse = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            completion(.failure(NSError(domain: "Invalid JSON response", code: -1, userInfo: nil)))
            return
        }
      
        if let errorDict = jsonResponse["error"] as? [String: Any], let errorMessage = errorDict["message"] as? String {
            completion(.failure(NSError(domain: errorMessage, code: -1, userInfo: nil)))
            return
        }
      
        guard let choices = jsonResponse["choices"] as? [[String: Any]],
              let choice = choices.first,
              let text = choice["text"] as? String
        else {
            completion(.failure(NSError(domain: "Invalid response structure", code: -1, userInfo: nil)))
            return
        }
      
        completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
    }.resume()
}

// Read command-line arguments
guard CommandLine.argc == 5 else {
    print("Usage: ./translate.swift <api_key> <language_code> <input_file> <output_file>")
    exit(1)
}

let apiKey = CommandLine.arguments[1]
let languageCode = CommandLine.arguments[2]
let inputFilePath = CommandLine.arguments[3]
let outputFilePath = CommandLine.arguments[4]

// Read the contents of the input file
guard let inputFileContents = try? String(contentsOfFile: inputFilePath, encoding: .utf8) else {
    print("Error: Unable to read input file.")
    exit(1)
}

// Create a semaphore to hold the main loop
let semaphore = DispatchSemaphore(value: 0)

// Send the entire input file to the ChatGPT API for translation
let prompt =
"""
Translate the following English text to the language of \"\(languageCode)\" ISO language code. Replace the English word after the = with it's translated equivalent in quotes. Preserve the rest of the formatting intact, including the text before the = and the terminating semi-colon. For example:

"English1" = "Spanish1";
"English2" = "Spanish2";

Translate the following:
\n\(inputFileContents)


"""

requestChatGPT(prompt: prompt, apiKey: apiKey) { result in
    switch result {
    case .success(let translatedText):
        // Write the translated contents to the output file
        do {
            try translatedText.write(toFile: outputFilePath, atomically: true, encoding: .utf8)
            print("Translation complete. Output saved to \(outputFilePath).")
        } catch {
            print("Error: Unable to write to output file.")
            exit(1)
        }
    case .failure(let error):
        print("Error: Unable to translate input file. \(error.localizedDescription)")
        exit(1)
    }
  
    semaphore.signal()
}

semaphore.wait()
