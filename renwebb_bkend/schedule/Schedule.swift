//
//  Schedule.swift
//  renwebb_bkend
//
//  Created by Tiger Wang on 5/22/18.
//  Copyright © 2018 Tiger Wang. All rights reserved.
//

import Foundation
import SwiftSoup
import Alamofire

class Schedule {
    
    var scheduleUrl: String
    var HWUrl: String?
    var CWUrl: String?
    var docDate: Date?
    var scheduleDoc: Document?
    var HWDoc: Document?
    var CWDoc: Document?
    var classCodeToName: [String: String]
    private var classes: [Class]
    
    init(scheduleUrl: String) {
        self.scheduleUrl = scheduleUrl
        classes = []
        classCodeToName = [:]
    }
    
    func getDay(date: Date, completion: @escaping ([Class]) -> ()) {
        HWUrl = Login.constructHWURL(weekOf: date)
        CWUrl = Login.constructCWURL(weekOf: date)
        // default Monday is 2, Monday needs to be 1, etc
        let weekday = Calendar.current.component(.weekday, from: date) - 1
        
        if scheduleDoc == nil && HWDoc == nil && CWDoc == nil {
            docDate = date
            getDocs(completion: { done in
                if done {
                    self.classes.removeAll()
                    self.parseClassCodeDictionary()
                    self.parseSchedule(weekday: weekday)
                    // use weekday for CW and HW
                    self.parseHW(date: date)
                    self.parseCW(date: date)
                    completion(self.classes)
                }
            })
        } else if Calendar.current.component(.weekOfYear, from: date) != Calendar.current.component(.weekOfYear, from: docDate!) {
            docDate = date
            getWeekDependentDocs(completion: { done in
                if done {
                    self.classes.removeAll()
                    self.parseSchedule(weekday: weekday)
                    // use weekday for CW and HW
                    self.parseHW(date: date)
                    self.parseCW(date: date)
                    completion(self.classes)
                }
            })
        } else {
            classes.removeAll()
            docDate = date
            parseSchedule(weekday: weekday)
            // use weekday for CW and HW
            parseHW(date: date)
            parseCW(date: date)
            completion(self.classes)
        }
        
    }
    
    private func getDocs(completion: @escaping (Bool) -> ()) {
        getScheduleDoc(completion: { done in
            if done {
                self.getHWDoc(completion: { done in
                    if done {
                        self.getCWDoc(completion: { done in
                            if done {
                                completion(true)
                            }
                        })
                    }
                })
            }
        })
    }
    
    private func getWeekDependentDocs(completion: @escaping (Bool) -> ()) {
        getHWDoc(completion: { done in
            if done {
                self.getCWDoc(completion: { done in
                    if done {
                        completion(true)
                    }
                })
            }
        })
    }
    
    private func getScheduleDoc(completion: @escaping (Bool) -> ()) {
        Alamofire.request(scheduleUrl).responseString { response in
            do {
                self.scheduleDoc = try SwiftSoup.parse(response.result.value!)
                completion(true)
            } catch {
                print("Error constructing schedule Document")
            }
        }
    }
    
    private func getHWDoc(completion: @escaping (Bool) -> ()) {
        Alamofire.request(HWUrl!).responseString { response in
            do {
                self.HWDoc = try SwiftSoup.parse(response.result.value!)
                if try self.HWDoc?.select("body > div").first()?.attr("id") == "main_content" {
                    completion(true)
                } else {
                    print("HW Session timed out... retrying login")
                    Login.attemptKeychainLogin(completion: { success in
                        if success {
                            Alamofire.request(self.HWUrl!).responseString { response in
                                do {
                                    self.HWDoc = try SwiftSoup.parse(response.result.value!)
                                    print("Re-logged in! returning Document")
                                    completion(true)
                                } catch {
                                    print("Error constructing HW Document")
                                }
                            }
                        } else {
                            print("Failed to re-log in... redirecting to login page")
                        }
                    })
                }
            } catch {
                print("Error constructing HW Document")
            }
        }
    }
    
    private func getCWDoc(completion: @escaping (Bool) -> ()) {
        Alamofire.request(CWUrl!).responseString { response in
            do {
                self.CWDoc = try SwiftSoup.parse(response.result.value!)
                if try self.HWDoc?.select("body > div").first()?.attr("id") == "main_content" {
                    completion(true)
                } else {
                    print("CW Session timed out... retrying login")
                    Login.attemptKeychainLogin(completion: { success in
                        if success {
                            Alamofire.request(self.CWUrl!).responseString { response in
                                do {
                                    self.CWDoc = try SwiftSoup.parse(response.result.value!)
                                    print("Re-logged in! returning Document")
                                    completion(true)
                                } catch {
                                    print("Error constructing HW Document")
                                }
                            }
                        } else {
                            print("Failed to re-log in... redirecting to login page")
                        }
                    })
                }
            } catch {
                print("Error constructing HW Document")
            }
        }
    }
    
    private func parseClassCodeDictionary() {
        print(scheduleDoc)
        if scheduleDoc != nil {
            do {
                let trs: Elements = try scheduleDoc!.select("body > table:nth-child(2) > tbody > tr")
                // Accounted for blank rows
                for i in 2...(trs.size() - 2) {
                    let tds = try trs.get(i).select("td")
                    classCodeToName[try tds.get(1).text()] = try tds.get(0).text()
                }
            } catch {
                print("Error parsing class code <-> name dictionary")
            }
        }
    }
    
    private func parseSchedule(weekday: Int) {
        if scheduleDoc != nil {
            do {
                let trs: Elements = try scheduleDoc!.select("#AutoNumber2 > tbody > tr")
                // Each class row contains 3 tr elements; i represents the index of the class row, not the tr element
                for i in 1...((trs.size() - 1) / 3) {
                    let classNameIndex = 3 * i - 2
                    let classTimeIndex = 3 * i - 1
                    let classLocIndex = 3 * i
                    let classCode: String = try trs.get(classNameIndex).select("td").get(weekday).text()
                    let className: String? = classCodeToName[classCode]
                    let classTime: String = try trs.get(classTimeIndex).select("td").get(weekday).text()
                    let classLoc: String = try trs.get(classLocIndex).select("td").get(weekday).text()
                    if className != nil && classTime != "" && classLoc != "" {
                        let newClass: Class = Class()
                        newClass.name = className!
                        newClass.time = classTime
                        newClass.loc = classLoc
                        classes.append(newClass)
                    }
                }
            } catch {
                print("Error parsing schedule Document")
            }
        }
    }
    
    private func parseHW(date: Date) {
        if HWDoc != nil {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd/yyyy"
            do {
                let lis: Elements = try HWDoc!.select("#main_content > ul > li")
                for li in lis {
                    let divs = try li.select("div")
                    let dateDiv = try divs.get(0).text()
                    if dateDiv.prefix(10) == formatter.string(from: date) {
                        
                        for i in 1...(divs.size() - 1) {
                            let div = divs.get(i)
                            let strong = try div.select("strong").text()
                            let divText = try div.text()
                            let indexOfDash = divText.index(of: "-")
                            let assignmentText = String(divText.suffix(from: indexOfDash!))
                            
                            for classEntry in self.classes {
                                if classEntry.name == strong {
                                    classEntry.HW = assignmentText
                                }
                            }
                        }
                        break
                        
                    }
                }
            } catch {
                print("Error parsing HW Document")
            }
        }
    }
    
    private func parseCW(date: Date) {
        if CWDoc != nil {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd/yyyy"
            do {
                let lis: Elements = try CWDoc!.select("#main_content > ul > li")
                for li in lis {
                    let divs = try li.select("div")
                    let dateDiv = try divs.get(0).text()
                    if dateDiv.prefix(10) == formatter.string(from: date) {
                        
                        for i in 1...(divs.size() - 1) {
                            let div = divs.get(i)
                            let strong = try div.select("span").text()
                            let divText = try div.text()
                            let indexOfDash = divText.index(of: "-")
                            let assignmentText = String(divText.suffix(from: indexOfDash!))
                            for classEntry in self.classes {
                                if classEntry.name == strong {
                                    classEntry.CW = assignmentText
                                }
                            }
                        }
                        break
                        
                    }
                }
            } catch {
                print("Error parsing HW Document")
            }
        }
    }
    
}
