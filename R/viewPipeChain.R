findPipeCalls <- function(x) {
  if (!is.call(x)) stop("expression is not a call", call. = FALSE)
  if (identical(x[[1]], quote(`do.call`)))
      stop("calls using do.call() are not supported", call. = FALSE)
  if (!identical(x[[1]], quote(`<-`)) &
      !identical(x[[1]], quote(`|>`)) &
      !identical(x[[1]], quote(`assign`)))
    stop("call is neither an assignment nor a pipe", call. = FALSE)
  pl <- list()
  done <- FALSE
  repeat{
    if (identical(x[[1]], quote(`<-`)) ||
        identical(x[[1]], quote(`assign`))) {
      x <- x[[3]]
      if (!is.call(x))
        stop("RHS of assignment does not contain call", call. = FALSE)
      if (!identical(x[[1]], quote(`|>`)))
        stop("RHS of assignment does not contain pipe", call. = FALSE)
    } else
    if (identical(x[[1]], quote(`|>`))) {
      pl <- c(pl, x[[3]])
      if (is.symbol(x[[2]]) || !identical(x[[2]][[1]], quote(`|>`))) {
        pl <- c(pl, x[[2]])
        done <- TRUE
      } else x <- x[[2]]
    }
    if (done) break
  }
  rev(pl)
}


processPipeChain <- function(cmd) {
  context <- rstudioapi::getActiveDocumentContext()
  selection <- context$selection[[1]]$text
  tryCatch({
    if (selection == "")
      stop("no text selected", call. = FALSE)
    call <- parse(text = selection)
    if(length(call) == 0)
      stop("selected text does not contain expression", call. = FALSE)
    call_list <- findPipeCalls(call[[1]])
    call_list_str <- as.character(call_list)
    for(i in 1:length(call_list)) {
      title <- sprintf("%d. %s", i, call_list_str[i])
      if (i == 1) ps1 <- eval(call_list[[i]]) else {
        call <- parse(text = paste(sprintf("ps%d %|>%", i - 1),
                                   paste0(deparse(call_list[[i]]),
                                          collapse = " ")))
        assign(sprintf("ps%d", i), eval(call))
      }
      assign(
        sprintf("obj%d", i),
        if (is.data.frame(get(sprintf("ps%d", i)))) {
          as.data.frame(get(sprintf("ps%d", i)))
        } else {
          get(sprintf("ps%d", i))
        }
      )
      if (i == 1 || !identical(get(sprintf("obj%d", i)),
                               get(sprintf("obj%d", i- 1))))
        eval(parse(text = sprintf(cmd, i)))
    }
  },
  error = function(e) {
    rstudioapi::showDialog("viewPipeChain",
                           paste("Sorry: ", e), url="")
    return()
  })
}

#' @title Creates a View() output for each pipe step in current text selection
#'
#' @description
#'   Reads the currently selected text from the RStudio API and displays a data view
#'   in the source pane for each pipe step creating a unique object.
#'   Meant to be called as an RStudio addin.
#'
#' @return No return value, called for side effects
#'
#' @export
viewPipeChain <- function() processPipeChain("View(ps%d, title = title)")

#' @title Prints each pipe step in current text selection
#'
#' @description
#'   Reads the currently selected text from the RStudio API and prints
#'   for each pipe step the resulting object if unique. Data frames are
#'   converted by as.tibble(). Meant to be called as an RStudio addin.
#'
#' @return No return value, called for side effects
#'
#' @export
printPipeChain <- function()
  processPipeChain(paste("message(title);",
                         "obj <- ps%d;",
                         "if (is.data.frame(obj)) obj <- tibble::as.tibble(obj);",
                         "print(obj)"))
